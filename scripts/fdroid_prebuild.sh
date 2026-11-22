#!/usr/bin/env bash
set -euo pipefail

# F-Droid prebuild script (runs while network access is available).
# Prepares a 100% FOSS, offline-buildable workspace without altering the main branch's
# Store/Desktop build configuration.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Pinned build inputs for reproducible F-Droid builds.
SQLITE_URL="https://sqlite.org/2025/sqlite-amalgamation-3490100.zip"
SQLITE_SHA256="6cebd1d8403fc58c30e93939b246f3e6e58d0765a5cd50546f16c00fd805d2c3"

FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-8.1.tar.xz"
FFMPEG_SHA256="b072aed6871998cce9b36e7774033105ca29e33632be5b6347f3206898e0756a"

OPUS_URL="https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz"
OPUS_SHA256="65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1"

LAME_REPO="https://github.com/axel10/lame-3.100"
LAME_COMMIT="056d86822562edff29bfbbfd6c4a218d4f04a72e"

RUST_FFMPEG_REPO="https://github.com/axel10/rust-ffmpeg"
RUST_FFMPEG_COMMIT="3e11215747e7b5c42dffb4cce3bc6f6a5f653ba4"

RUST_TOOLCHAIN="1.95.0"

verify_sha256() {
  local expected_sha="$1"
  local file_path="$2"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s  %s\n' "$expected_sha" "$file_path" | sha256sum -c -
  else
    printf '%s  %s\n' "$expected_sha" "$file_path" | shasum -a 256 -c -
  fi
}

clone_pinned_commit() {
  local repo_url="$1"
  local commit_sha="$2"
  local dest_dir="$3"
  rm -rf "$dest_dir"
  mkdir -p "$dest_dir"
  git -C "$dest_dir" init -q
  git -C "$dest_dir" remote add origin "$repo_url"
  git -C "$dest_dir" fetch --depth 1 origin "$commit_sha"
  git -C "$dest_dir" checkout -q FETCH_HEAD
}

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
if [[ ! -f "$SQLITE_DIR/sqlite3.c" ]]; then
  mkdir -p "$SQLITE_DIR"
  TMP_ZIP="$(mktemp)"
  curl -fsSL "$SQLITE_URL" -o "$TMP_ZIP"
  verify_sha256 "$SQLITE_SHA256" "$TMP_ZIP"
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
  curl -fsSL "$FFMPEG_URL" -o "$AUDIO_CORE_DIR/ffmpeg-8.1.tar.xz"
  verify_sha256 "$FFMPEG_SHA256" "$AUDIO_CORE_DIR/ffmpeg-8.1.tar.xz"
  python3 -c 'import sys, tarfile; tarfile.open(sys.argv[1], "r:xz").extractall(sys.argv[2])' \
    "$AUDIO_CORE_DIR/ffmpeg-8.1.tar.xz" "$AUDIO_CORE_DIR"
  rm -f "$AUDIO_CORE_DIR/ffmpeg-8.1.tar.xz"
fi

if [[ ! -d "$AUDIO_CORE_DIR/opus-1.5.2" ]]; then
  curl -fsSL "$OPUS_URL" -o "$AUDIO_CORE_DIR/opus-1.5.2.tar.gz"
  verify_sha256 "$OPUS_SHA256" "$AUDIO_CORE_DIR/opus-1.5.2.tar.gz"
  tar -xzf "$AUDIO_CORE_DIR/opus-1.5.2.tar.gz" -C "$AUDIO_CORE_DIR"
  rm -f "$AUDIO_CORE_DIR/opus-1.5.2.tar.gz"
fi

if [[ ! -d "$AUDIO_CORE_DIR/lame-3.100" ]]; then
  clone_pinned_commit "$LAME_REPO" "$LAME_COMMIT" "$AUDIO_CORE_DIR/lame-3.100"
fi

if [[ ! -d "$AUDIO_CORE_DIR/rust/rust-ffmpeg/.git" ]]; then
  clone_pinned_commit "$RUST_FFMPEG_REPO" "$RUST_FFMPEG_COMMIT" "$AUDIO_CORE_DIR/rust/rust-ffmpeg"
fi

# Remove any prebuilt ffmpeg_lib so F-Droid builds it cleanly from source in the build phase.
rm -rf "$AUDIO_CORE_DIR/android/ffmpeg_lib" "$AUDIO_CORE_DIR/android/src/main/jniLibs"

echo "==> [5/5] Prefetching Flutter, Android CMake & Rust dependencies for offline build..."
SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/opt/android-sdk}}"
if [[ -d "$SDK_ROOT" && ! -d "$SDK_ROOT/cmake/3.22.1" ]]; then
  SDKMANAGER_BIN="$(command -v sdkmanager || true)"
  if [[ -z "$SDKMANAGER_BIN" ]]; then
    for candidate in \
      "$SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" \
      "$SDK_ROOT/tools/bin/sdkmanager"; do
      if [[ -x "$candidate" ]]; then
        SDKMANAGER_BIN="$candidate"
        break
      fi
    done
  fi
  if [[ -n "$SDKMANAGER_BIN" ]]; then
    yes | "$SDKMANAGER_BIN" "cmake;3.22.1" >/dev/null || "$SDKMANAGER_BIN" "cmake;3.22.1"
  fi
fi

if command -v rustup >/dev/null 2>&1; then
  rustup toolchain install "$RUST_TOOLCHAIN" --profile minimal
  rustup default "$RUST_TOOLCHAIN"
  rustup target add aarch64-linux-android --toolchain "$RUST_TOOLCHAIN"
fi

flutter pub get
if [[ -f "$AUDIO_CORE_DIR/rust/Cargo.toml" ]]; then
  (cd "$AUDIO_CORE_DIR/rust" && cargo fetch)
fi

echo "F-Droid prebuild preparation complete."
