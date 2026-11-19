#!/usr/bin/env bash
set -euo pipefail

# F-Droid prebuild script (runs while network access is available).
# Prepares a 100% FOSS, offline-buildable workspace without altering the main branch's
# Store/Desktop build configuration.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> [1/5] Replacing IAP service with FOSS stub..."
cp "$ROOT_DIR/scripts/fdroid/iap_service_stub.dart" "$ROOT_DIR/lib/player/pro/iap_service.dart"

echo "==> [2/5] Stripping proprietary IAP dependencies & configuring SQLite source build in pubspec.yaml..."
python3 - "$ROOT_DIR/pubspec.yaml" <<'PY'
import sys

pubspec_path = sys.argv[1]
with open(pubspec_path, "r", encoding="utf-8") as f:
    lines = f.readlines()

filtered = []
skip_next_sdk_flutter = False
for line in lines:
    stripped = line.strip()
    if skip_next_sdk_flutter:
        if stripped == "sdk: flutter":
            skip_next_sdk_flutter = False
            continue
        skip_next_sdk_flutter = False
    if stripped.startswith("in_app_purchase:") or stripped.startswith("in_app_purchase_storekit:"):
        continue
    if stripped == "integration_test:":
        skip_next_sdk_flutter = True
        continue
    filtered.append(line)

content = "".join(filtered)

hook_marker = "  user_defines:\n    sqlite3:"
if hook_marker not in content:
    hooks_block = (
        "\nhooks:\n"
        "  user_defines:\n"
        "    sqlite3:\n"
        "      source: source\n"
        "      path: third_party/sqlite/sqlite3.c\n"
    )
    content = content.rstrip() + "\n" + hooks_block

with open(pubspec_path, "w", encoding="utf-8") as f:
    f.write(content)
PY

echo "==> [3/5] Downloading SQLite amalgamation source..."
SQLITE_DIR="$ROOT_DIR/third_party/sqlite"
SQLITE_URL="https://sqlite.org/2025/sqlite-amalgamation-3490100.zip"
if [[ ! -f "$SQLITE_DIR/sqlite3.c" ]]; then
  mkdir -p "$SQLITE_DIR"
  TMP_ZIP="$(mktemp)"
  curl -fsSL "$SQLITE_URL" -o "$TMP_ZIP"
  TMP_EXTRACT="$(mktemp -d)"
  unzip -q "$TMP_ZIP" -d "$TMP_EXTRACT"
  cp "$TMP_EXTRACT"/sqlite-amalgamation-*/sqlite3.c "$SQLITE_DIR/"
  cp "$TMP_EXTRACT"/sqlite-amalgamation-*/sqlite3.h "$SQLITE_DIR/"
  rm -rf "$TMP_ZIP" "$TMP_EXTRACT"
else
  echo "SQLite amalgamation already present at $SQLITE_DIR/sqlite3.c."
fi

echo "==> [4/5] Fetching audio_core FOSS media sources (FFmpeg, Opus, LAME, rust-ffmpeg)..."
AUDIO_CORE_DIR="$ROOT_DIR/audio_core"
if [[ ! -d "$AUDIO_CORE_DIR/ffmpeg-8.1" ]]; then
  curl -fsSL "https://ffmpeg.org/releases/ffmpeg-8.1.tar.xz" -o "$AUDIO_CORE_DIR/ffmpeg-8.1.tar.xz"
  tar -xJf "$AUDIO_CORE_DIR/ffmpeg-8.1.tar.xz" -C "$AUDIO_CORE_DIR"
  rm -f "$AUDIO_CORE_DIR/ffmpeg-8.1.tar.xz"
fi

if [[ ! -d "$AUDIO_CORE_DIR/opus-1.5.2" ]]; then
  curl -fsSL "https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz" -o "$AUDIO_CORE_DIR/opus-1.5.2.tar.gz"
  tar -xzf "$AUDIO_CORE_DIR/opus-1.5.2.tar.gz" -C "$AUDIO_CORE_DIR"
  rm -f "$AUDIO_CORE_DIR/opus-1.5.2.tar.gz"
fi

if [[ ! -d "$AUDIO_CORE_DIR/lame-3.100" ]]; then
  git clone --depth 1 "https://github.com/axel10/lame-3.100" "$AUDIO_CORE_DIR/lame-3.100"
fi

if [[ ! -d "$AUDIO_CORE_DIR/rust/rust-ffmpeg/.git" ]]; then
  rm -rf "$AUDIO_CORE_DIR/rust/rust-ffmpeg"
  git clone --depth 1 "https://github.com/axel10/rust-ffmpeg" "$AUDIO_CORE_DIR/rust/rust-ffmpeg"
fi

# Remove any prebuilt ffmpeg_lib so F-Droid builds it cleanly from source in the build phase.
rm -rf "$AUDIO_CORE_DIR/android/ffmpeg_lib" "$AUDIO_CORE_DIR/android/src/main/jniLibs"

echo "==> [5/5] Prefetching Flutter & Rust dependencies for offline build..."
flutter pub get
if [[ -f "$AUDIO_CORE_DIR/rust/Cargo.toml" ]]; then
  (cd "$AUDIO_CORE_DIR/rust" && cargo fetch)
fi

echo "F-Droid prebuild preparation complete."
