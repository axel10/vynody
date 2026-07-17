#!/usr/bin/env bash

# This script generates offline dependency files required for Flathub.
# It produces cargo-sources.json (from Cargo.lock) and pub-sources.json (from pubspec.lock).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Processing Rust/Cargo Dependencies ==="
CARGO_LOCK="$ROOT_DIR/audio_core/rust/Cargo.lock"
CARGO_OUTPUT="$SCRIPT_DIR/cargo-sources.json"

if [[ ! -f "$CARGO_LOCK" ]]; then
  echo "Error: Cargo.lock not found at $CARGO_LOCK" >&2
  exit 1
fi

CARGO_GEN_URL="https://raw.githubusercontent.com/flatpak/flatpak-builder-tools/master/cargo/flatpak-cargo-generator.py"
CARGO_GEN_TEMP=$(mktemp)

echo "Downloading flatpak-cargo-generator.py..."
if command -v curl >/dev/null 2>&1; then
  curl -L -s -o "$CARGO_GEN_TEMP" "$CARGO_GEN_URL"
elif command -v wget >/dev/null 2>&1; then
  wget -q -O "$CARGO_GEN_TEMP" "$CARGO_GEN_URL"
else
  echo "Error: curl or wget is required." >&2
  exit 1
fi

echo "Running cargo dependency generator..."
# Note: flatpak-cargo-generator.py requires python3 and tomlkit or similar python libraries.
# If they are missing, it falls back to installing them or prompting the user.
if python3 "$CARGO_GEN_TEMP" "$CARGO_LOCK" -o "$CARGO_OUTPUT"; then
  echo "Successfully generated cargo-sources.json at $CARGO_OUTPUT"
else
  echo "Failed to run flatpak-cargo-generator.py automatically." >&2
  echo "Please run it manually: python3 flatpak-cargo-generator.py audio_core/rust/Cargo.lock -o packaging/flatpak/cargo-sources.json" >&2
fi
rm -f "$CARGO_GEN_TEMP"

echo ""
echo "=== Processing Dart/Flutter Dependencies ==="
PUB_LOCK="$ROOT_DIR/pubspec.lock"
PUB_OUTPUT="$SCRIPT_DIR/pub-sources.json"

if [[ ! -f "$PUB_LOCK" ]]; then
  echo "Error: pubspec.lock not found. Please run 'flutter pub get' in the root first." >&2
  exit 1
fi

if command -v dart >/dev/null 2>&1; then
  echo "Dart SDK found. Activating flutpak..."
  dart pub global activate flutpak >/dev/null 2>&1 || true
  
  if command -v flutpak >/dev/null 2>&1 || dart pub global run flutpak --version >/dev/null 2>&1; then
    echo "Running flutpak generate..."
    cd "$ROOT_DIR"
    if dart pub global run flutpak generate; then
      if [[ -f "$ROOT_DIR/generated-sources.json" ]]; then
        mv "$ROOT_DIR/generated-sources.json" "$PUB_OUTPUT"
        echo "Successfully generated pub-sources.json at $PUB_OUTPUT"
      fi
    else
      echo "Flutpak generation failed." >&2
    fi
  else
    echo "Failed to run flutpak. Please make sure pub global binaries are in your PATH." >&2
    echo "Refer to https://github.com/o-murphy/flutpak for manual steps." >&2
  fi
else
  echo "Dart SDK not found in PATH." >&2
  echo "Please install Dart/Flutter, then run: " >&2
  echo "  dart pub global activate flutpak" >&2
  echo "  flutpak generate" >&2
  echo "  mv generated-sources.json packaging/flatpak/pub-sources.json" >&2
fi

echo ""
echo "Done! Manifest files are configured inside packaging/flatpak/"
