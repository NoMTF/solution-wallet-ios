#!/usr/bin/env bash
# 在模拟器里装上 App、启动、截图。
#
# 存在的理由：开发机是 Windows，打不开 Xcode 也跑不了模拟器，改完界面看不到效果。
# 这个脚本把截图当成 CI 产物传回来，等于把「改完看一眼」这个回路搬到云上。
set -euo pipefail

SHOTS="build/shots"
mkdir -p "$SHOTS"

APP=$(find build/dd/Build/Products -maxdepth 2 -name "*.app" | head -1)
if [ -z "$APP" ]; then
    echo "找不到模拟器构建产物，构建步骤应该已经失败了" >&2
    exit 1
fi
echo "App: $APP"

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
echo "Bundle ID: $BUNDLE_ID"

# 挑一台可用的 iPhone。不写死型号，Xcode 版本一换型号列表就会变。
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
data = json.load(sys.stdin)["devices"]
best = None
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    for d in devices:
        if not d.get("isAvailable"):
            continue
        name = d["name"]
        if "iPhone" not in name:
            continue
        # 优先 Pro，其次任意 iPhone；同时取最新 runtime
        score = (1 if "Pro" in name else 0, runtime)
        if best is None or score > best[0]:
            best = (score, d["udid"], name, runtime)
if best is None:
    sys.exit("没有可用的 iPhone 模拟器")
print(best[1])
print(best[2], best[3], file=sys.stderr)
')
echo "模拟器 UDID: $UDID"

cleanup() { xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b

# 深色外观：这个 App 本身是深色调，浅色下截图看不出真实观感
xcrun simctl ui "$UDID" appearance dark >/dev/null 2>&1 || true

xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null

# 首屏往往有启动动画与异步加载，隔几秒连拍几张，能看清稳定后的样子
for i in 1 2 3; do
    sleep 5
    xcrun simctl io "$UDID" screenshot "$SHOTS/0$i-launch.png" >/dev/null 2>&1 || true
    echo "已截图 0$i"
done

# 确认进程还活着——崩溃时截图可能只是一张残留画面，容易误判成「界面正常」
if xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -q "$BUNDLE_ID"; then
    echo "进程存活：启动正常"
else
    echo "::warning::App 进程不在了，可能启动即崩溃" >&2
    CRASH_DIR="$HOME/Library/Logs/DiagnosticReports"
    if [ -d "$CRASH_DIR" ]; then
        mkdir -p "$SHOTS/../crashes"
        find "$CRASH_DIR" -name "*.ips" -newermt "-10 minutes" -exec cp {} "$SHOTS/../crashes/" \; 2>/dev/null || true
        echo "崩溃报告已收集到 build/crashes"
    fi
fi

ls -la "$SHOTS"
