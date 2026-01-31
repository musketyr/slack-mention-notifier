#!/bin/bash
set -euo pipefail

# Build a proper macOS .app bundle from the Swift binary
# Usage: ./scripts/bundle-app.sh [version]

VERSION="${1:-0.1.0}"
APP_NAME="Slack Mention Notifier"
BINARY_NAME="SlackMentionNotifier"
BUNDLE_DIR="dist/${APP_NAME}.app"

echo "📦 Building ${APP_NAME} v${VERSION}..."

# 1. Build universal binary (arm64 + x86_64)
echo "🔨 Building arm64..."
swift build -c release --arch arm64

echo "🔨 Building x86_64..."
swift build -c release --arch x86_64

echo "🔨 Creating universal binary..."
mkdir -p dist
lipo -create \
    .build/arm64-apple-macosx/release/${BINARY_NAME} \
    .build/x86_64-apple-macosx/release/${BINARY_NAME} \
    -output dist/${BINARY_NAME}

# 2. Create .app bundle structure
echo "📁 Creating app bundle..."
rm -rf "${BUNDLE_DIR}"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
mkdir -p "${BUNDLE_DIR}/Contents/Resources"

# Copy binary
cp dist/${BINARY_NAME} "${BUNDLE_DIR}/Contents/MacOS/${BINARY_NAME}"

# Copy and patch Info.plist
sed "s/__VERSION__/${VERSION}/g" resources/Info.plist > "${BUNDLE_DIR}/Contents/Info.plist"

# Create PkgInfo
echo -n "APPL????" > "${BUNDLE_DIR}/Contents/PkgInfo"

# Create .icns icon
echo "🎨 Creating app icon..."
ICONSET="dist/AppIcon.iconset"
rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"

# Generate icon sizes from SVG (requires rsvg-convert or sips on macOS)
for size in 16 32 64 128 256 512; do
    size2x=$((size * 2))
    if command -v sips &> /dev/null; then
        sips -z ${size} ${size} resources/icon_1024.png --out "${ICONSET}/icon_${size}x${size}.png" &>/dev/null
        sips -z ${size2x} ${size2x} resources/icon_1024.png --out "${ICONSET}/icon_${size}x${size}@2x.png" &>/dev/null
    else
        convert -resize ${size}x${size} resources/icon_1024.png "${ICONSET}/icon_${size}x${size}.png"
        convert -resize ${size2x}x${size2x} resources/icon_1024.png "${ICONSET}/icon_${size}x${size}@2x.png"
    fi
done

iconutil -c icns "${ICONSET}" -o "${BUNDLE_DIR}/Contents/Resources/AppIcon.icns"
rm -rf "${ICONSET}"

echo "✅ App bundle created: ${BUNDLE_DIR}"

# 3. Create DMG
DMG_NAME="SlackMentionNotifier-${VERSION}.dmg"
echo "💿 Creating DMG..."

# Create a temporary directory for DMG contents
DMG_STAGE="dist/dmg-stage"
rm -rf "${DMG_STAGE}"
mkdir -p "${DMG_STAGE}"
cp -R "${BUNDLE_DIR}" "${DMG_STAGE}/"
ln -s /Applications "${DMG_STAGE}/Applications"

hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGE}" \
    -ov -format UDZO \
    "dist/${DMG_NAME}"

rm -rf "${DMG_STAGE}"

echo "✅ DMG created: dist/${DMG_NAME}"
echo ""
echo "To test: open dist/${DMG_NAME}"
