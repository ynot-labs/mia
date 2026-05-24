#!/bin/bash
set -euo pipefail

APP_NAME="Mia"
BUNDLE_ID="com.mia.translator"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/.build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
ENTITLEMENTS="$ROOT/Resources/Mia.entitlements"

echo "=== Building Swift binary ==="
cd "$ROOT"
swift build

echo "=== Creating app bundle ==="
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/debug/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>Mia</string>
	<key>CFBundleDisplayName</key>
	<string>Mia 同声传译</string>
	<key>CFBundleIdentifier</key>
	<string>com.mia.translator</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleExecutable</key>
	<string>Mia</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>Mia 需要访问麦克风以采集您的语音进行实时翻译。</string>
	<key>NSScreenCaptureUsageDescription</key>
	<string>Mia 需要「屏幕录制」权限以采集会议应用的音频进行实时翻译。Mia 不会录制或保存您的屏幕画面。</string>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
PLIST_EOF

# Copy entitlements
cp "$ENTITLEMENTS" "$APP_DIR/Contents/Resources/"

# Ad-hoc sign with entitlements
echo "=== Signing with entitlements ==="
codesign --force --deep --sign - \
    --entitlements "$ENTITLEMENTS" \
    "$APP_DIR"

echo ""
echo "=== Done: $APP_DIR ==="
echo "Run: open $APP_DIR"
