#!/bin/bash
set -e

APP_NAME="ESP-BOX"

echo "============================================"
echo "  ESP-BOX iOS Build"
echo "============================================"

# Get iOS SDK path
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
echo "[*] SDK Path: $SDK_PATH"

# Verify SDK exists
if [ ! -d "$SDK_PATH" ]; then
    echo "[!] iOS SDK not found!"
    exit 1
fi

# Collect all Swift source files
SWIFT_FILES=(
    "Sources/ESP_BOXApp.swift"
    "Sources/ContentView.swift"
    "Sources/Core/ProcessFinder.swift"
    "Sources/Core/MemoryManager.swift"
    "Sources/Core/MLBBOffsets.swift"
    "Sources/Core/EntityParser.swift"
    "Sources/Overlay/OverlayWindow.swift"
    "Sources/Overlay/ESPRenderer.swift"
)

# Verify all files exist
for f in "${SWIFT_FILES[@]}"; do
    if [ ! -f "$f" ]; then
        echo "[!] Missing file: $f"
        exit 1
    fi
done

echo "[*] Found ${#SWIFT_FILES[@]} Swift files"

# Compile for arm64 iOS
echo "[*] Compiling..."
swiftc \
    -target arm64-apple-ios15.0 \
    -sdk "$SDK_PATH" \
    -o "$APP_NAME" \
    -parse-as-library \
    -emit-executable \
    -O \
    -swift-version 5 \
    "${SWIFT_FILES[@]}"

if [ $? -ne 0 ]; then
    echo "[!] Compilation failed!"
    exit 1
fi

echo "[*] Compilation successful"

# Verify binary
file "$APP_NAME"

# Create .app bundle
echo "[*] Creating app bundle..."
APP_DIR="${APP_NAME}.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"

cp "$APP_NAME" "$APP_DIR/"
cp Config/Info.plist "$APP_DIR/"

# Sign with entitlements using ldid
echo "[*] Signing with entitlements..."
ldid -S Config/ESP_BOX.entitlements "$APP_DIR/$APP_NAME"

if [ $? -ne 0 ]; then
    echo "[!] Signing failed!"
    exit 1
fi

# Verify signature
echo "[*] Verifying signature..."
ldid -e "$APP_DIR/$APP_NAME"

# Package as IPA
echo "[*] Packaging IPA..."
rm -rf Payload "${APP_NAME}.ipa"
mkdir Payload
cp -r "$APP_DIR" Payload/
zip -r "${APP_NAME}.ipa" Payload
rm -rf Payload

echo "[*] Cleaning up..."
rm -rf "$APP_DIR" "$APP_NAME"

echo ""
echo "============================================"
echo "  BUILD COMPLETE"
echo "============================================"
ls -la "${APP_NAME}.ipa"
echo ""
