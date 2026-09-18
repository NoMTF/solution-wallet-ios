#!/usr/bin/env bash
# 从模板生成 Config.xcconfig。
#
# 上游把 Config.xcconfig 放进了 .gitignore（里面全是 API key），所以每次构建都要现生成。
# 取值来源是环境变量 XCCONFIG_<KEY>，由 GitHub Secrets 注入；没配的键留空。
#
# 留空是安全的：对应功能会降级（比如没有 explorer key 就少一个交易历史数据源），
# 但 App 能正常构建和启动。我们自己加的功能一个 key 都不需要。
set -euo pipefail

CONFIG_DIR="Unstoppable/Unstoppable/Configuration"
TEMPLATE="$CONFIG_DIR/Config.template.xcconfig"
OUTPUT="$CONFIG_DIR/Config.xcconfig"

if [ ! -f "$TEMPLATE" ]; then
    echo "找不到模板 $TEMPLATE —— 上游可能挪了位置" >&2
    exit 1
fi

: >"$OUTPUT"
filled=0
empty=0

while IFS= read -r line || [ -n "$line" ]; do
    # 只处理 "KEY =" 这种行，注释和空行原样保留
    if [[ "$line" =~ ^([A-Z0-9_]+)[[:space:]]*=(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        env_name="XCCONFIG_${key}"
        value="${!env_name-}"

        if [ -n "$value" ]; then
            filled=$((filled + 1))
        else
            empty=$((empty + 1))
        fi
        echo "$key = $value" >>"$OUTPUT"
    else
        echo "$line" >>"$OUTPUT"
    fi
done <"$TEMPLATE"

echo "已生成 ${OUTPUT}：$filled 个键有值，$empty 个留空"

# 绝不能把 key 打进日志，所以只列出键名
echo "有值的键："
grep -E '^[A-Z0-9_]+ = .+$' "$OUTPUT" | cut -d' ' -f1 | tr '\n' ' ' || true
echo
