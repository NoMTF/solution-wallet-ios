#!/usr/bin/env bash
# 把未签名的 .xcarchive 打成可侧载的 IPA。
#
# 为什么不用 `xcodebuild -exportArchive`：它的每一种 exportMethod 都要求有证书和
# provisioning profile，而我们刻意不签名——签名交给 SideStore 在设备上完成。
# IPA 本质上就是「Payload/ 目录里放一个 .app」的 zip，所以手工打包最干净。
set -euo pipefail

ARCHIVE="${1:-build/Solution.xcarchive}"
OUT_DIR="${2:-build}"

APP_DIR="$ARCHIVE/Products/Applications"
if [ ! -d "$APP_DIR" ]; then
    echo "归档里没有 $APP_DIR —— 归档步骤应该已经失败了" >&2
    exit 1
fi

APP=$(find "$APP_DIR" -maxdepth 1 -name "*.app" | head -1)
if [ -z "$APP" ]; then
    echo "在 $APP_DIR 里找不到 .app" >&2
    exit 1
fi

NAME=$(basename "$APP" .app)
STAGE="$OUT_DIR/ipa-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"

# 清掉残留的签名与描述文件。CODE_SIGNING_ALLOWED=NO 时本来就不该有，
# 但 SPM 依赖里偶尔会带进来，留着会让 SideStore 重签时报错。
find "$STAGE/Payload" -name "_CodeSignature" -type d -prune -exec rm -rf {} + 2>/dev/null || true
find "$STAGE/Payload" -name "embedded.mobileprovision" -delete 2>/dev/null || true

# 先把打进包里的扩展列出来再收尾。免费 Apple 证书不支持 App Group 之外的很多能力，
# 万一装不上，这份清单是第一个排查线索。
echo "包内扩展："
APPEX=$(find "$STAGE/Payload" -name "*.appex" 2>/dev/null || true)
if [ -n "$APPEX" ]; then
    echo "$APPEX" | while read -r ext; do echo "  $(basename "$ext")"; done
else
    echo "  （无）"
fi

IPA="$OUT_DIR/$NAME-unsigned.ipa"
rm -f "$IPA"
(cd "$STAGE" && zip -qry "../$(basename "$IPA")" Payload)
rm -rf "$STAGE"

echo "已生成 $IPA（$(du -h "$IPA" | cut -f1)）"
