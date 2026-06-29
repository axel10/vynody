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

# Extract version from pubspec.yaml
VERSION=$(grep '^version: ' pubspec.yaml | cut -d ' ' -f 2 | tr '+' '-')
DMG_NAME="vynody-macos-$VERSION.dmg"

echo -e "${BLUE}==> 6. Preparing DMG staging directory...${NC}"
rm -rf vynody-dmg
mkdir -p vynody-dmg
cp -R build/macos/Build/Products/Release/Vynody.app vynody-dmg/
ln -s /Applications vynody-dmg/Applications

# Auto-detect signing identity if not set
if [ -z "$MACOS_SIGNING_IDENTITY" ]; then
    DETECTED_IDENTITY=$(security find-identity -v -p codesigning | grep -o 'Developer ID Application: [^"]*' | head -n 1)
    if [ -n "$DETECTED_IDENTITY" ]; then
        MACOS_SIGNING_IDENTITY="$DETECTED_IDENTITY"
        echo -e "${GREEN}Automatically detected signing identity: $MACOS_SIGNING_IDENTITY${NC}"
    fi
fi

if [ -n "$MACOS_SIGNING_IDENTITY" ]; then
    echo -e "${BLUE}==> 6a. Recursively code signing app bundle...${NC}"
    
    # 1. Sign all dylibs
    find "vynody-dmg/Vynody.app" -name "*.dylib" -type f | while read -r file; do
        echo "Signing dylib: $file"
        codesign --force --options runtime --sign "$MACOS_SIGNING_IDENTITY" --timestamp "$file"
    done

    # 2. Sign all frameworks (deepest first)
    find "vynody-dmg/Vynody.app" -name "*.framework" -type d | awk '{ print length, $0 }' | sort -nr | cut -d' ' -f2- | while read -r framework; do
        echo "Signing framework: $framework"
        codesign --force --options runtime --sign "$MACOS_SIGNING_IDENTITY" --timestamp "$framework"
    done

    # 3. Sign other Mach-O files (executables, etc.) not already inside frameworks or signed as dylibs
    find "vynody-dmg/Vynody.app" -type f | while read -r file; do
        if [[ "$file" == *.dylib || "$file" == *.framework/* ]]; then
            continue
        fi
        if file "$file" | grep -q "Mach-O"; then
            echo "Signing Mach-O executable: $file"
            codesign --force --options runtime --sign "$MACOS_SIGNING_IDENTITY" --timestamp "$file"
        fi
    done

    # 4. Sign the outer Vynody.app bundle with entitlements
    echo "Signing Vynody.app bundle with entitlements..."
    codesign --force --options runtime --entitlements macos/Runner/Release.entitlements --sign "$MACOS_SIGNING_IDENTITY" --timestamp vynody-dmg/Vynody.app
else
    echo -e "${RED}Warning: MACOS_SIGNING_IDENTITY not set and no Developer ID Application certificate found. Falling back to ad-hoc signing...${NC}"
    codesign --force --deep --sign - --preserve-metadata=entitlements,identifier,flags vynody-dmg/Vynody.app
fi

echo -e "${BLUE}==> 7. Creating DMG package: $DMG_NAME...${NC}"
rm -f "$DMG_NAME"
hdiutil create \
  -volname "Vynody" \
  -srcfolder vynody-dmg \
  -ov \
  -format UDZO \
  "$DMG_NAME"

# Sign and notarize the DMG if signing identity is set
if [ -n "$MACOS_SIGNING_IDENTITY" ]; then
    echo -e "${BLUE}==> 7a. Signing DMG...${NC}"
    codesign --force --sign "$MACOS_SIGNING_IDENTITY" --timestamp "$DMG_NAME"
    
    if [ -n "$APPLE_ID" ] && [ -n "$APP_SPECIFIC_PASSWORD" ] && [ -n "$TEAM_ID" ]; then
        echo -e "${BLUE}==> 7b. Submitting DMG for notarization...${NC}"
        xcrun notarytool submit "$DMG_NAME" \
          --apple-id "$APPLE_ID" \
          --password "$APP_SPECIFIC_PASSWORD" \
          --team-id "$TEAM_ID" \
          --wait
        
        echo -e "${BLUE}==> 7c. Stapling notarization ticket to DMG...${NC}"
        xcrun stapler staple "$DMG_NAME"
        
        echo -e "${GREEN}==> Verifying signature and notarization...${NC}"
        spctl --assess --type open --context context:primary-signature --verbose "$DMG_NAME"
    else
        echo -e "${RED}Warning: APPLE_ID, APP_SPECIFIC_PASSWORD, or TEAM_ID not set. Skipping notarization.${NC}"
    fi
fi

echo -e "${BLUE}==> 8. Cleaning up staging directory...${NC}"
rm -rf vynody-dmg

echo -e "${GREEN}==> Done! DMG created successfully at: ./$DMG_NAME${NC}"
