#!/usr/bin/env bash
# CI 脚本的自检。
#
# 存在的理由：`echo "已生成 $OUTPUT：..."` 这种写法让 bash 把全角冒号当成变量名的一部分，
# 去找一个叫 `OUTPUT：` 的变量，在 set -u 下直接 unbound variable 而整个构建失败。
# 错误信息里的变量名还因为编码看不出所以然，排查成本极高——而修复只是加个花括号。
# 这类问题在中文注释密集的脚本里几乎必然复发，所以让机器来盯。
set -euo pipefail

SCRIPTS=$(find .github/scripts -name "*.sh")
fail=0

for f in $SCRIPTS; do
    # 1. 语法检查
    if ! bash -n "$f"; then
        echo "::error file=$f::bash 语法错误"
        fail=1
    fi

    # 2. 变量后紧跟非 ASCII 字符（必须用 ${} 包起来）
    if grep -nP '\$[A-Za-z_][A-Za-z0-9_]*(?=[^\x00-\x7F])' "$f" >/dev/null 2>&1; then
        echo "::error file=$f::变量后面紧跟着非 ASCII 字符，bash 会把它并进变量名。请改用 \${VAR}"
        grep -nP '\$[A-Za-z_][A-Za-z0-9_]*(?=[^\x00-\x7F])' "$f" | sed 's/^/    /'
        fail=1
    fi

    # 3. CRLF 会让 macOS 上的 shebang 报 bad interpreter
    if grep -q $'\r' "$f"; then
        echo "::error file=$f::含有 CRLF 换行，macOS 上会报 bad interpreter"
        fail=1
    fi
done

if [ "$fail" -eq 0 ]; then
    echo "脚本自检通过：$(echo "$SCRIPTS" | wc -l | tr -d ' ') 个文件"
fi
exit "$fail"
