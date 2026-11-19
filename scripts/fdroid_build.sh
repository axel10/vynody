#!/usr/bin/env bash
set -euo pipefail

# F-Droid offline build script.
# Compiles FFmpeg from source with the Android NDK, marks version.txt so Gradle's
# downloadFFmpeg task skips network access, and builds release APKs.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
if [[ ! -d "$SDK_ROOT" ]]; then
  echo "Error: Android SDK not found at '$SDK_ROOT'. Set ANDROID_HOME or ANDROID_SDK_ROOT." >&2
  exit 1
fi

JOBS="${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

echo "==> [1/3] Compiling FFmpeg/Opus/LAME from source for Android (armeabi-v7a, arm64-v8a)..."
"$ROOT_DIR/audio_core/build-ffmpeg-android.sh" \
  --sdk "$SDK_ROOT" \
  --jobs "$JOBS" \
  --abi armeabi-v7a \
  --abi arm64-v8a

echo "==> [2/3] Writing ffmpeg_lib/version.txt from audio_core/ffmpeg_version.env..."
FFMPEG_VERSION="$(grep '^FFMPEG_VERSION=' "$ROOT_DIR/audio_core/ffmpeg_version.env" | cut -d '=' -f 2 | tr -d '"\r' | xargs)"
if [[ -z "$FFMPEG_VERSION" ]]; then
  echo "Error: Failed to read FFMPEG_VERSION from audio_core/ffmpeg_version.env" >&2
  exit 1
fi
printf '%s' "$FFMPEG_VERSION" > "$ROOT_DIR/audio_core/android/ffmpeg_lib/version.txt"

echo "==> [3/3] Building Flutter release APKs (offline)..."
export CARGO_NET_OFFLINE=true
flutter build apk --release \
  --no-pub \
  --target-platform android-arm,android-arm64 \
  --split-per-abi

echo "F-Droid build finished successfully."
