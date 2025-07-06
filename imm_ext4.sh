#!/bin/bash
set -e # 如果任何命令失败，立即退出脚本

mkdir -p imm

REPO="m2kall/AutoBuildImmortalWrt"
TAG="Autobuild-x86-64"
FILE_NAME="immortalwrt-24.10.2-x86-64-generic-ext4-combined-efi.img.gz"
OUTPUT_PATH="imm/immortalwrt.img.gz"
UNZIPPED_IMG_PATH="imm/immortalwrt.img"

DOWNLOAD_URL=$(curl -s "https://api.github.com/repos/$REPO/releases/tags/$TAG" | jq --arg name "$FILE_NAME" -r '.assets[] | select(.name == $name) | .browser_download_url')

if [[ -z "$DOWNLOAD_URL" ]]; then
  echo "错误：在 Release 中未找到文件 $FILE_NAME"
  exit 1
fi

echo "下载地址: $DOWNLOAD_URL"
echo "开始下载文件: $FILE_NAME -> $OUTPUT_PATH"
curl -L -o "$OUTPUT_PATH" "$DOWNLOAD_URL"

echo "下载成功!"
file "$OUTPUT_PATH"

echo "正在解压文件: $OUTPUT_PATH -> $UNZIPPED_IMG_PATH"

# 【重要修正】使用 gunzip -c 并显式处理退出码
# gunzip -c 将解压内容输出到标准输出，我们将其重定向到新文件
# 然后我们检查退出码，$?。如果退出码不是 0 (成功) 也不是 2 (警告)，才算失败。
gunzip -c "$OUTPUT_PATH" > "$UNZIPPED_IMG_PATH" || {
    exit_code=$?
    if [ $exit_code -ne 2 ]; then
        echo "错误：解压失败，出现严重错误，退出码: $exit_code"
        exit $exit_code
    fi
    echo "解压成功，并忽略了可预期的 'trailing garbage' 警告。"
}

# 成功解压后，删除原始的 .gz 文件
rm "$OUTPUT_PATH"

echo "解压完成。imm/ 目录内容:"
ls -lh imm/

if [ ! -f "$UNZIPPED_IMG_PATH" ]; then
    echo "错误：解压后未找到预期的文件 $UNZIPPED_IMG_PATH"
    exit 1
fi

echo "准备使用 Docker 合成 immortalwrt 安装器..."
docker run --privileged --rm \
      -v "$(pwd)/output:/output" \
      -v "$(pwd)/supportFiles:/supportFiles:ro" \
      -v "$(pwd)/$UNZIPPED_IMG_PATH:/mnt/immortalwrt.img" \
      debian:buster \
      /supportFiles/immortalwrt/build.sh

echo "所有步骤成功完成!"
