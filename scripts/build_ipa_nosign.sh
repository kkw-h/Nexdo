#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

if ! command -v flutter >/dev/null 2>&1; then
  echo "[IPA] 未检测到 flutter 命令，请先安装 Flutter SDK" >&2
  exit 1
fi

VERSION=$(sed -n 's/^version:[[:space:]]*\([^+[:space:]]*\).*/\1/p' "$PROJECT_ROOT/pubspec.yaml" | head -n 1)
if [ -n "${1:-}" ]; then
  VERSION="$1"
fi

if [ -z "$VERSION" ]; then
  echo "[IPA] 无法从 pubspec.yaml 读取版本号" >&2
  exit 1
fi

IPA_DIR="$PROJECT_ROOT/build/ios/ipa"
IPA_NAME="nexdo-${VERSION}-nosign.ipa"
APP_PATH="$PROJECT_ROOT/build/ios/iphoneos/Runner.app"

echo "=== 构建 iOS 无签名 IPA ($VERSION) ==="

cd "$PROJECT_ROOT"

flutter pub get

echo ">>> flutter build ios --release --no-codesign"
flutter build ios --release --no-codesign

if [ ! -d "$APP_PATH" ]; then
  echo "[IPA] 未找到 Runner.app，构建失败" >&2
  exit 1
fi

echo ">>> 打包 IPA..."
mkdir -p "$IPA_DIR"
TMP_DIR=$(mktemp -d)
mkdir -p "$TMP_DIR/Payload"
cp -R "$APP_PATH" "$TMP_DIR/Payload/Runner.app"

(
  cd "$TMP_DIR"
  zip -qr "$IPA_DIR/$IPA_NAME" Payload
)

rm -rf "$TMP_DIR"

echo
echo "=== 完成 ==="
echo "IPA 路径: $IPA_DIR/$IPA_NAME"
ls -lh "$IPA_DIR/$IPA_NAME"
