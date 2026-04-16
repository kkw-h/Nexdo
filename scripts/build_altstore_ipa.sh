#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
用法: ./scripts/build_altstore_ipa.sh [--tag <git_tag>]

说明:
  - 构建 AltStore 可用的 IPA（未签名），输出到 build/altstore。
  - 根据 pubspec.yaml 自动读取版本号。
  - 默认假设 GitHub Release 标签为 v<version>，可通过 --tag 自定义。
  - 构建完成后，会更新 altstore/source.json，填充 GitHub Release 下载地址与文件大小。
EOF
}

RELEASE_TAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      if [[ $# -lt 2 ]]; then
        echo "[AltStore] --tag 需要一个值" >&2
        exit 1
      fi
      RELEASE_TAG="$2"
      shift 2
      ;;
    --tag=*)
      RELEASE_TAG="${1#*=}"
      shift 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[AltStore] 未知参数: $1" >&2
      usage
      exit 1
      ;;
  esac
done

for cmd in flutter python3 zip; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[AltStore] 未检测到 $cmd，请先安装对应工具" >&2
    exit 1
  fi
done

VERSION_LINE=$(sed -n 's/^version:[[:space:]]*//p' "$ROOT_DIR/pubspec.yaml" | head -n 1)
if [[ -z "$VERSION_LINE" ]]; then
  echo "[AltStore] 无法从 pubspec.yaml 读取 version 字段" >&2
  exit 1
fi

APP_VERSION="${ALTSTORE_APP_VERSION:-${VERSION_LINE%%+*}}"
if [[ -z "$APP_VERSION" ]]; then
  echo "[AltStore] version 字段格式异常: $VERSION_LINE" >&2
  exit 1
fi

RELEASE_TAG=${RELEASE_TAG:-"v$APP_VERSION"}

OUTPUT_DIR="$ROOT_DIR/build/altstore"
PAYLOAD_DIR="$OUTPUT_DIR/Payload"
APP_PATH="$ROOT_DIR/build/ios/Release-iphoneos/Runner.app"
IPA_NAME="Nexdo-AltStore-${APP_VERSION}.ipa"
IPA_PATH="$OUTPUT_DIR/$IPA_NAME"

SOURCE_JSON="$ROOT_DIR/altstore/source.json"
SOURCE_URL_DEFAULT="https://raw.githubusercontent.com/kkw-h/Nexdo/main/altstore/source.json"
SOURCE_URL="${ALTSTORE_SOURCE_URL:-$SOURCE_URL_DEFAULT}"
ICON_URL_DEFAULT="https://raw.githubusercontent.com/kkw-h/Nexdo/main/assets/app_icon.png"
ICON_URL="${ALTSTORE_ICON_URL:-$ICON_URL_DEFAULT}"
DOWNLOAD_URL_BASE="${ALTSTORE_DOWNLOAD_BASE:-https://github.com/kkw-h/Nexdo/releases/download}"
DOWNLOAD_URL="$DOWNLOAD_URL_BASE/$RELEASE_TAG/$IPA_NAME"
VERSION_DATE=$(date -u +%Y-%m-%d)
VERSION_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
RELEASE_NOTES="${ALTSTORE_RELEASE_NOTES:-Nexdo ${APP_VERSION} 发布}"

echo "=== 构建 AltStore IPA (${APP_VERSION}) ==="
flutter pub get
flutter build ios --release --no-codesign

if [[ ! -d "$APP_PATH" ]]; then
  echo "[AltStore] 未找到 Runner.app，构建失败" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -rf "$PAYLOAD_DIR"
rm -f "$IPA_PATH"
mkdir -p "$PAYLOAD_DIR"
cp -R "$APP_PATH" "$PAYLOAD_DIR/Runner.app"

(cd "$OUTPUT_DIR" && zip -qr "$IPA_NAME" Payload)
rm -rf "$PAYLOAD_DIR"

python3 <<PY
import json
import os
from pathlib import Path

source_path = Path("$SOURCE_JSON")
if not source_path.exists():
  raise SystemExit(f"[AltStore] 未找到 {source_path}")

data = json.loads(source_path.read_text(encoding="utf-8"))
data["name"] = data.get("name") or "Nexdo"
data["identifier"] = "top.kkworld.nexdo"
data["sourceURL"] = "$SOURCE_URL"

apps = data.setdefault("apps", [])
if not apps:
  apps.append({})
app = apps[0]
app.setdefault("name", "Nexdo")
app["bundleIdentifier"] = "top.kkworld.nexdo"
app["developerName"] = app.get("developerName") or "Nexdo Team"
app["iconURL"] = "$ICON_URL"
app.setdefault("localizedDescription", "Nexdo 是一个专注于提醒和闪念管理的应用，支持清单、分组、标签以及 Go API 同步。")
app.setdefault("screenshotURLs", [])
app.setdefault("tintColor", "#126A5A")
app["appPermissions"] = {
    "entitlements": [],
    "privacy": {
        "NSUserNotificationsUsageDescription": "Nexdo 会使用通知来提醒你按时处理事项。"
    },
}

for legacy_key in ("version", "versionDate", "downloadURL", "size"):
    app.pop(legacy_key, None)

versions = [v for v in app.get("versions", []) if v.get("version") != "$APP_VERSION"]
versions.insert(
    0,
    {
        "version": "$APP_VERSION",
        "date": "$VERSION_ISO",
        "localizedDescription": "$RELEASE_NOTES",
        "downloadURL": "$DOWNLOAD_URL",
        "size": os.path.getsize("$IPA_PATH"),
    },
)
app["versions"] = versions

source_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

cat <<EOF
[AltStore] 构建完成：$IPA_PATH
[AltStore] 已更新 altstore/source.json
[AltStore] GitHub Release 标签: $RELEASE_TAG
[AltStore] 下载 URL: $DOWNLOAD_URL

下一步:
1. 将 $IPA_PATH 上传到 GitHub Release ($RELEASE_TAG) 并命名为 ${IPA_NAME}。
2. 确保 altstore/source.json 也托管在可公开访问的 ${SOURCE_URL}。
3. 在 AltStore 中添加该 Source URL，即可安装/更新 Nexdo。
EOF
