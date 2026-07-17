#!/usr/bin/env bash

# This script rebuilds the Vynody app locally and installs it in the user Flatpak environment.
# Perfect for quickly testing source code modifications inside the Flatpak sandbox.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== 1. Running Flutter Release Build ==="
cd "$ROOT_DIR"
flutter build linux --release

echo "=== 2. Re-building and Installing Flatpak Package ==="
flatpak-builder --user --install --force-clean build-flatpak packaging/flatpak/io.github.axel10.vynody.local.yml

echo ""
echo "============================================="
echo "🎉 Update successful!"
echo "Run the Flatpak app via:"
echo "  flatpak run io.github.axel10.vynody"
echo "============================================="
