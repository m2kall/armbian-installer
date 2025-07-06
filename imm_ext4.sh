#!/bin/bash
set -e # 如果任何命令失败，立即退出脚本

mkdir -p imm

REPO="m2kall/AutoBuildImmortalWrt"
TAG="Autobuild-x86-64"
FILE_NAME="immortalwrt-24.10.2-x86-64-generic-ext4-combined-efi.img.gz"
OUTPUT_PATH="imm/immortalwrt.img.gz"
UNZIPPED_IMG_PATH="imm/immortalwrt.img"

DOWNLOAD_URL=$(curl -s https://api.github.com/repos/$REPO/releases/tags/$TAG | jq -r '.assets[] | select(.name == "''"$FILE_NAME"''") | .browser_download_url')

if [[ -z "$DOWNLOAD_URL" ]]; then
  echo "错误：在 Release 中未找到文件 $FILE_NAME"
  exit 1
fi

echo "下载地址: $DOWNLOAD_URL"
echo "开始下载文件: $FILE_NAME -> $OUTPUT_PATH"
curl -L -o "$OUTPUT_PATH" "$DOWNLOAD_URL"

if [[ $? -eq 0 ]]; then
  echo "下载成功!"
  file "$OUTPUT_PATH"
  
  echo "正在解压文件: $OUTPUT_PATH"
  # 【重要修正】使用正确的文件名进行解压
  gzip -d "$OUTPUT_PATH"
  
  echo "解压完成。imm/ 目录内容:"
  ls -lh imm/

  # 检查解压后的文件是否存在
  if [ ! -f "$UNZIPPED_IMG_PATH" ]; then
      echo "错误：解压失败，未找到预期的文件 $UNZIPPED_IMG_PATH"
      exit 1
  fi

  echo "准备使用 Docker 合成 immortalwrt 安装器..."
  docker run --privileged --rm \
        -v "$(pwd)/output:/output" \
        -v "$(pwd)/supportFiles:/supportFiles:ro" \
        -v "$(pwd)/$UNZIPPED_IMG_PATH:/mnt/immortalwrt.img" \
        debian:buster \
        /supportFiles/immortalwrt/build.sh
else
  echo "下载失败!"
  exit 1
fi
