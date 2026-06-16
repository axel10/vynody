#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==> 1. Checking environment...${NC}"

# Check for flutter
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}Error: flutter is not installed or not in PATH.${NC}"
    exit 1
fi

# Ensure Flutter Swift Package Manager for plugins is disabled to prevent dynamic framework linking bugs with Cargokit
flutter config --no-enable-swift-package-manager > /dev/null

# Check for rustup and targets
if command -v rustup &> /dev/null; then
    echo -e "${BLUE}Checking Rust targets...${NC}"
    rustup target add x86_64-apple-darwin aarch64-apple-darwin
else
    echo -e "${RED}Warning: rustup not found. Rust target check skipped.${NC}"
fi

echo -e "${BLUE}==> 2. Fetching Flutter dependencies...${NC}"
flutter pub get

echo -e "${BLUE}==> 3. Cleaning previous macOS builds...${NC}"
rm -rf build/macos

echo -e "${BLUE}==> 4. Resolving Swift Package dependencies...${NC}"
xcodebuild -resolvePackageDependencies \
  -workspace macos/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -derivedDataPath build/macos/resolve \
  -clonedSourcePackagesDirPath build/macos/SourcePackages

echo -e "${BLUE}==> 5. Building macOS Release application...${NC}"
CXXFLAGS="-std=gnu++20" flutter build macos --release

echo -e "${BLUE}==> 6. Preparing DMG staging directory...${NC}"
rm -rf vynody-dmg
mkdir -p vynody-dmg
cp -R build/macos/Build/Products/Release/Vynody.app vynody-dmg/
codesign --force --deep --sign - --preserve-metadata=entitlements,identifier,flags vynody-dmg/Vynody.app
ln -s /Applications vynody-dmg/Applications

echo -e "${BLUE}==> 7. Creating DMG package...${NC}"
hdiutil create \
  -volname "Vynody" \
  -srcfolder vynody-dmg \
  -ov \
  -format UDZO \
  vynody-macos.dmg

echo -e "${BLUE}==> 8. Cleaning up staging directory...${NC}"
rm -rf vynody-dmg

echo -e "${GREEN}==> Done! DMG created successfully at: ./vynody-macos.dmg${NC}"
