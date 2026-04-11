#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

if ! command -v flutter >/dev/null 2>&1; then
  echo "[AltStore] 未检测到 flutter 命令，请先安装 Flutter SDK" >&2
  exit 1
fi

flutter pub get
flutter build ipa --release --no-codesign

OUTPUT_DIR="$ROOT_DIR/build/altstore"
mkdir -p "$OUTPUT_DIR"
IPA_SRC="$ROOT_DIR/build/ios/ipa/Runner.ipa"
IPA_DST="$OUTPUT_DIR/Nexdo-AltStore.ipa"

if [ ! -f "$IPA_SRC" ]; then
  echo "[AltStore] 构建成功但未找到 Runner.ipa，Flutter 版本可能发生变化，请检查" >&2
  exit 1
fi

cp "$IPA_SRC" "$IPA_DST"

cat <<MSG
[AltStore] 构建完成：$IPA_DST
可将该文件导入 AltStore (My Apps -> +) 进行安装，AltStore 会在安装时重新签名。
MSG
