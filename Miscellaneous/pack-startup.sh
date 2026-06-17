#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -lt 1 ]]; then
  echo "用法: $0 原始脚本.sh [输出开机脚本.sh]"
  echo "示例: $0 bootstrap.sh startup_ready.sh"
  exit 1
fi

INPUT_SCRIPT="$1"
OUTPUT_SCRIPT="${2:-startup_ready.sh}"

[[ -f "$INPUT_SCRIPT" ]] || {
  echo "错误: 找不到输入脚本: $INPUT_SCRIPT" >&2
  exit 1
}

TMP_LF="$(mktemp /tmp/source_lf.XXXXXX.sh)"
TMP_B64="$(mktemp /tmp/source_b64.XXXXXX.txt)"

cleanup() {
  rm -f "$TMP_LF" "$TMP_B64"
}
trap cleanup EXIT

# 1. 转 LF，避免 Windows CRLF 导致 bash 报错
sed 's/\r$//' "$INPUT_SCRIPT" > "$TMP_LF"

# 2. 确保文件最后有 LF
printf '\n' >> "$TMP_LF"

# 3. 先检查原脚本语法
bash -n "$TMP_LF"

# 4. gzip + base64
# gzip -n: 不写入原文件名和时间戳，输出更稳定
gzip -n -9 -c "$TMP_LF" | base64 > "$TMP_B64"

# 5. 生成完整可执行开机脚本
cat > "$OUTPUT_SCRIPT" <<'HEADER'
#!/usr/bin/env bash
set -Eeuo pipefail

TMP_SCRIPT="$(mktemp /tmp/launch.XXXXXX.sh)"

cleanup() {
  rm -f "$TMP_SCRIPT"
}
trap cleanup EXIT

base64 -d <<'__LAUNCH_GZIP_B64__' | gzip -d > "$TMP_SCRIPT"
HEADER

cat "$TMP_B64" >> "$OUTPUT_SCRIPT"

cat >> "$OUTPUT_SCRIPT" <<'FOOTER'
__LAUNCH_GZIP_B64__

chmod 700 "$TMP_SCRIPT"
bash -n "$TMP_SCRIPT"
bash "$TMP_SCRIPT"
FOOTER

chmod 700 "$OUTPUT_SCRIPT"

# 6. 检查生成出来的开机脚本语法
bash -n "$OUTPUT_SCRIPT"

echo "完成: $OUTPUT_SCRIPT"
echo
echo "你可以直接把这个文件内容复制到 VPS 开机脚本里:"
echo "cat $OUTPUT_SCRIPT"