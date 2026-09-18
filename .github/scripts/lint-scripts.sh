#!/usr/bin/env bash
# CI 脚本的自检。
#
# 存在的理由：中文全角标点如果紧跟在 shell 变量后面，bash 会把它并进变量名，
# 于是去找一个根本不存在的变量，在 set -u 下直接 unbound variable 而整个构建失败。
# 错误信息里的变量名还因为编码看不出所以然，排查成本远高于修复成本（加个花括号而已）。
# 这类问题在中文注释密集的脚本里几乎必然复发，所以让机器来盯。
#
# 正则部分用 python3 而不是 `grep -P`：Windows 上的 Git bash 自带的 grep 没有 PCRE，
# `grep -P` 会直接失败返回非零，被误当成「没有匹配」，于是检查器静默失效。
# 用 python3 才能保证本地和 CI 跑出同样的结果。
set -euo pipefail

fail=0
for f in $(find .github/scripts -name "*.sh"); do
    if ! bash -n "$f"; then
        echo "::error file=$f::bash 语法错误"
        fail=1
    fi
done

# 不能只看命令存不存在：Windows 的 Git bash 里 python3 是个商店占位程序，
# 文件在、一跑就失败。所以实际执行一下再决定用哪个。
PY_BIN=""
for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c "pass" >/dev/null 2>&1; then
        PY_BIN="$candidate"
        break
    fi
done
if [ -z "$PY_BIN" ]; then
    echo "::error::找不到可用的 python，无法执行检查"
    exit 1
fi

"$PY_BIN" - <<'PY' || fail=1
import glob
import re
import sys

# 变量名后面紧跟非 ASCII 字符
bad_var = re.compile(r"\$[A-Za-z_][A-Za-z0-9_]*(?=[^\x00-\x7F])")
problems = 0
checked = 0

for path in sorted(glob.glob(".github/scripts/*.sh")):
    checked += 1
    raw = open(path, "rb").read()

    if b"\r" in raw:
        print(f"::error file={path}::含有 CRLF 换行，macOS 上会报 bad interpreter")
        problems += 1

    for number, line in enumerate(raw.decode("utf-8").split("\n"), start=1):
        # 注释里出现只是举例说明，不算问题
        if line.lstrip().startswith("#"):
            continue
        if bad_var.search(line):
            print(
                f"::error file={path},line={number}::"
                "变量后面紧跟着非 ASCII 字符，bash 会把它并进变量名。请改用 ${VAR}"
            )
            print(f"    {line.strip()}")
            problems += 1

if problems:
    sys.exit(1)
print(f"脚本自检通过：{checked} 个文件")
PY

exit "$fail"
