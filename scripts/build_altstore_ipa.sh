#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

if ! command -v flutter >/dev/null 2>&1; then
  echo "[AltStore] 未检测到 flutter 命令，请先安装 Flutter SDK" >&2
  exit 1
fi

flutter pub get
flutter build ios --release --no-codesign

APP_PATH="$ROOT_DIR/build/ios/iphoneos/Runner.app"
if [ ! -d "$APP_PATH" ]; then
  echo "[AltStore] 未找到 Runner.app，构建失败" >&2
  exit 1
fi

OUTPUT_DIR="$ROOT_DIR/build/altstore"
PAYLOAD_DIR="$OUTPUT_DIR/Payload"
mkdir -p "$PAYLOAD_DIR"
rm -rf "$PAYLOAD_DIR/Runner.app"
cp -R "$APP_PATH" "$PAYLOAD_DIR/Runner.app"

(cd "$OUTPUT_DIR" && zip -r Nexdo-AltStore.ipa Payload >/dev/null)
rm -rf "$PAYLOAD_DIR"

cat <<MSG
[AltStore] 构建完成：$OUTPUT_DIR/Nexdo-AltStore.ipa
将该文件拖入 AltStore (My Apps -> +) 即可安装，AltStore 会在安装时重新签名。
MSG
