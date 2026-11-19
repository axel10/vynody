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

echo "==> [1/3] Compiling FFmpeg/Opus/LAME from source for Android (arm64-v8a)..."
bash "$ROOT_DIR/audio_core/build-ffmpeg-android.sh" \
  --sdk "$SDK_ROOT" \
  --jobs "$JOBS" \
  --abi arm64-v8a

echo "==> [2/3] Writing ffmpeg_lib/version.txt from audio_core/ffmpeg_version.env..."
FFMPEG_VERSION="$(grep '^FFMPEG_VERSION=' "$ROOT_DIR/audio_core/ffmpeg_version.env" | cut -d '=' -f 2 | tr -d '"\r' | xargs)"
if [[ -z "$FFMPEG_VERSION" ]]; then
  echo "Error: Failed to read FFMPEG_VERSION from audio_core/ffmpeg_version.env" >&2
  exit 1
fi
printf '%s' "$FFMPEG_VERSION" > "$ROOT_DIR/audio_core/android/ffmpeg_lib/version.txt"

echo "==> [3/3] Building Flutter release APK (offline, arm64-v8a)..."
if [[ -z "${LIBCLANG_PATH:-}" ]]; then
  NDK_SEARCH_ROOT="${ANDROID_NDK_HOME:-${NDK_HOME:-}}"
  LIBCLANG_DIR=""
  if [[ -n "$NDK_SEARCH_ROOT" && -d "$NDK_SEARCH_ROOT" ]]; then
    LIBCLANG_CANDIDATE="$(find "$NDK_SEARCH_ROOT/toolchains/llvm/prebuilt" -maxdepth 3 \( -name "libclang.so" -o -name "libclang.so.*" -o -name "libclang.dylib" \) 2>/dev/null | head -n 1 || true)"
    if [[ -n "$LIBCLANG_CANDIDATE" ]]; then
      LIBCLANG_DIR="$(dirname "$LIBCLANG_CANDIDATE")"
    fi
  elif [[ -d "$SDK_ROOT/ndk" ]]; then
    while IFS= read -r ndk_dir; do
      LIBCLANG_CANDIDATE="$(find "$ndk_dir/toolchains/llvm/prebuilt" -maxdepth 3 \( -name "libclang.so" -o -name "libclang.so.*" -o -name "libclang.dylib" \) 2>/dev/null | head -n 1 || true)"
      if [[ -n "$LIBCLANG_CANDIDATE" ]]; then
        LIBCLANG_DIR="$(dirname "$LIBCLANG_CANDIDATE")"
        break
      fi
    done < <(find "$SDK_ROOT/ndk" -mindepth 1 -maxdepth 1 -type d | sort -r)
  fi

  if [[ -z "$LIBCLANG_DIR" ]]; then
    echo "Error: Could not locate libclang in Android NDK under '$SDK_ROOT/ndk'. Set LIBCLANG_PATH manually." >&2
    exit 1
  fi
  export LIBCLANG_PATH="$LIBCLANG_DIR"
  echo "Using NDK LIBCLANG_PATH=$LIBCLANG_PATH"
fi

export CARGO_NET_OFFLINE=true
flutter build apk --release \
  --no-pub \
  --target-platform android-arm64 \
  --split-per-abi

echo "F-Droid build finished successfully."
