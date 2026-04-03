#!/bin/bash
# Yaksok — build, package, and codesign
#
# Usage: ./build.sh [--sign] [--zip]
#   --sign  Sign with Developer ID (required for distribution)
#   --zip   Create Yaksok-VERSION.zip for Sparkle update distribution
set -euo pipefail

cd "$(dirname "$0")"

PROJ_DIR="$(pwd)"
APP_DIR="$PROJ_DIR/Yaksok.app"
BUILD_DIR="$PROJ_DIR/.build"
SPARKLE_FW="$BUILD_DIR/arm64-apple-macosx/release/Sparkle.framework"
SPARKLE_TOOLS="$BUILD_DIR/artifacts/sparkle/Sparkle/bin"
SIGN_ID="Developer ID Application: Yoonseok Jang (DT9JQA4X82)"
SDK=$(xcrun --show-sdk-path)

# Parse flags
DO_SIGN=false
DO_ZIP=false
for arg in "$@"; do
    case "$arg" in
        --sign) DO_SIGN=true ;;
        --zip)  DO_ZIP=true ;;
    esac
done

echo "=== Yaksok Build ==="

# 1. Build release
echo "[1/6] Building release..."
swift build -c release 2>&1 | tail -5

# 2. Build Share Extension
echo "[2/6] Building Share Extension..."
SHARE_DIR="$BUILD_DIR/share"
mkdir -p "$SHARE_DIR"
swiftc \
    -parse-as-library \
    -module-name YaksokShare \
    -target arm64-apple-macos14 \
    -sdk "$SDK" \
    -framework Cocoa \
    -framework UniformTypeIdentifiers \
    -Xlinker -e -Xlinker _NSExtensionMain \
    -application-extension \
    -o "$SHARE_DIR/YaksokShare" \
    Sources/YaksokShare/ShareViewController.swift 2>&1 || echo "  (Share Extension build skipped)"

# 3. Package .app bundle
echo "[3/6] Packaging .app..."
cp -f "$BUILD_DIR/release/Yaksok" "$APP_DIR/Contents/MacOS/Yaksok"
cp -f Resources/Info.plist "$APP_DIR/Contents/Info.plist"
VERSION=$(defaults read "$APP_DIR/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0.0")
echo "    Version: $VERSION"
mkdir -p "$APP_DIR/Contents/Resources"
cp -f Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns" 2>/dev/null || true

# Package Share Extension
if [ -f "$SHARE_DIR/YaksokShare" ]; then
    APPEX="$APP_DIR/Contents/PlugIns/YaksokShare.appex"
    mkdir -p "$APPEX/Contents/MacOS"
    mkdir -p "$APPEX/Contents/Resources"
    cp -f "$SHARE_DIR/YaksokShare" "$APPEX/Contents/MacOS/"
    cp -f Sources/YaksokShare/Info.plist "$APPEX/Contents/"
    cp -f Resources/AppIcon.icns "$APPEX/Contents/Resources/AppIcon.icns" 2>/dev/null || true
    echo "  Share Extension packaged"
fi

# 4. Embed Sparkle framework
echo "[4/6] Embedding Sparkle framework..."
mkdir -p "$APP_DIR/Contents/Frameworks"
rm -rf "$APP_DIR/Contents/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
    cp -a "$SPARKLE_FW" "$APP_DIR/Contents/Frameworks/"
    echo "  Sparkle.framework embedded"
else
    echo "  WARNING: Sparkle.framework not found at $SPARKLE_FW"
    echo "  Run 'swift build -c release' first to fetch Sparkle."
fi

# Add rpath for Sparkle framework
install_name_tool -add_rpath @executable_path/../Frameworks \
    "$APP_DIR/Contents/MacOS/Yaksok" 2>/dev/null || true

# 5. Code sign
if $DO_SIGN; then
    echo "[5/6] Signing with Developer ID (in /tmp to avoid Dropbox xattr)..."
    SIGN_DIR="/tmp/Yaksok-sign-$$"
    rm -rf "$SIGN_DIR"
    mkdir -p "$SIGN_DIR"
    cp -R "$APP_DIR" "$SIGN_DIR/"

    # Clean all Dropbox/Finder metadata
    find "$SIGN_DIR" -name "._*" -delete 2>/dev/null
    dot_clean "$SIGN_DIR/Yaksok.app" 2>/dev/null || true
    find "$SIGN_DIR" -exec xattr -c {} \; 2>/dev/null

    # Fix permissions (Dropbox copies with 700, Sparkle needs 755)
    find "$SIGN_DIR/Yaksok.app" -type d -exec chmod 755 {} \;
    find "$SIGN_DIR/Yaksok.app" -type f -exec chmod 644 {} \;
    find "$SIGN_DIR/Yaksok.app" -path "*/MacOS/*" -type f -exec chmod 755 {} \;
    find "$SIGN_DIR/Yaksok.app" -name "Autoupdate" -type f -exec chmod 755 {} \;

    S="$SIGN_DIR/Yaksok.app"

    # Sign inside-out: Share Extension → Sparkle internals → Sparkle framework → app
    if [ -d "$S/Contents/PlugIns/YaksokShare.appex" ]; then
        codesign --force --sign "$SIGN_ID" --options runtime "$S/Contents/PlugIns/YaksokShare.appex"
    fi

    if [ -d "$S/Contents/Frameworks/Sparkle.framework" ]; then
        codesign --force --sign "$SIGN_ID" --options runtime \
            "$S/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
        codesign --force --sign "$SIGN_ID" --options runtime \
            "$S/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
        codesign --force --sign "$SIGN_ID" --options runtime \
            "$S/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
        codesign --force --sign "$SIGN_ID" --options runtime \
            "$S/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
        codesign --force --sign "$SIGN_ID" --options runtime \
            "$S/Contents/Frameworks/Sparkle.framework"
    fi

    codesign --force --sign "$SIGN_ID" --options runtime \
        --entitlements "$PROJ_DIR/Resources/Yaksok.entitlements" "$S"

    # Verify
    if codesign --verify --deep --strict "$S" 2>&1; then
        echo "    Verification: PASSED"
        echo "    $(codesign -dv "$S" 2>&1 | grep 'Authority=' | head -1)"
    else
        echo "    Verification: FAILED"
        rm -rf "$SIGN_DIR"
        exit 1
    fi

    # Copy signed app back and clean Dropbox xattr (TCC requires clean signatures)
    rm -rf "$APP_DIR"
    cp -R "$S" "$APP_DIR"
    xattr -cr "$APP_DIR" 2>/dev/null || true

    # Notarize
    if $DO_ZIP; then
        ZIP_NAME="Yaksok-${VERSION}.zip"
        echo ""
        echo "=== Notarizing ==="
        # Create temporary ZIP for notarization submission
        NOTARY_ZIP="/tmp/Yaksok-notarize-$$.zip"
        cd "$SIGN_DIR"
        ditto -c -k --sequesterRsrc --keepParent Yaksok.app "$NOTARY_ZIP"
        if xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "Yaksok-Notary" --wait 2>&1; then
            echo "    Notarization: ACCEPTED"
            xcrun stapler staple "$S"
            echo "    Staple: DONE"
        else
            echo "    Notarization: FAILED (continuing without notarization)"
        fi
        rm -f "$NOTARY_ZIP"

        # Create final ZIP from notarized+stapled app
        echo ""
        echo "=== Creating $ZIP_NAME ==="
        rm -f "$PROJ_DIR/$ZIP_NAME"
        ditto -c -k --sequesterRsrc --keepParent Yaksok.app "$PROJ_DIR/$ZIP_NAME"
        echo "    Size: $(du -h "$PROJ_DIR/$ZIP_NAME" | cut -f1)"

        echo ""
        echo "=== Sparkle signature ==="
        if [ -x "$SPARKLE_TOOLS/sign_update" ]; then
            "$SPARKLE_TOOLS/sign_update" "$PROJ_DIR/$ZIP_NAME"
            echo ""
            echo "Update appcast.xml with the above edSignature and length."
        else
            echo "    WARNING: sign_update not found at $SPARKLE_TOOLS"
            echo "    Run 'swift build -c release' to get Sparkle tools."
        fi
    fi

    rm -rf "$SIGN_DIR"
else
    echo "[5/6] Ad-hoc signing..."
    xattr -rc "$APP_DIR" 2>/dev/null || true
    # Sign Share Extension first
    if [ -d "$APP_DIR/Contents/PlugIns/YaksokShare.appex" ]; then
        codesign --force --sign - --options runtime "$APP_DIR/Contents/PlugIns/YaksokShare.appex"
    fi
    codesign --force --deep --sign - --options runtime \
        --entitlements "$PROJ_DIR/Resources/Yaksok.entitlements" "$APP_DIR"

    if $DO_ZIP; then
        ZIP_NAME="Yaksok-${VERSION}.zip"
        echo ""
        echo "=== Creating $ZIP_NAME (ad-hoc signed) ==="
        rm -f "$PROJ_DIR/$ZIP_NAME"
        ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$PROJ_DIR/$ZIP_NAME"
        echo "    Size: $(du -h "$PROJ_DIR/$ZIP_NAME" | cut -f1)"
    fi
fi

# 6. Refresh Services
echo "[6/6] Refreshing Services..."
/System/Library/CoreServices/pbs -flush 2>/dev/null || true
/System/Library/CoreServices/pbs -update 2>/dev/null || true

echo ""
echo "=== Done! ==="
echo "App: $APP_DIR"
echo "Version: $VERSION"
echo "Run: open Yaksok.app"
