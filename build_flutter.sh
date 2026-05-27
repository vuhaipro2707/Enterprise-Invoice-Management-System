#!/bin/bash
# build_flutter.sh
# Usage: Called from cd_ssh.sh (REMOTE_SERVER and REMOTE_PATH must be set)
# Or run standalone: ./build_flutter.sh user@host /remote/path

# Allow override from args if called standalone
REMOTE_SERVER="${REMOTE_SERVER:-$1}"
REMOTE_PATH="${REMOTE_PATH:-$2}"

UPLOAD=true
if [ -z "$REMOTE_SERVER" ] || [ -z "$REMOTE_PATH" ]; then
    UPLOAD=false
fi

FRONTEND_DIR="./invoice_app_frontend"
WEB_BUILD_DIR="$FRONTEND_DIR/build/web"
APK_BUILD_PATH="$FRONTEND_DIR/build/app/outputs/flutter-apk/app-release.apk"

if [ "$UPLOAD" = true ]; then
    echo "--- Flutter Build & Upload ---"
else
    echo "--- Flutter Build (Local Only) ---"
fi
echo ""

# --- Flutter Web ---
BUILD_WEB=true
if [ -d "$WEB_BUILD_DIR" ]; then
    read -p "Flutter Web build already exists. Rebuild? (y/N): " REBUILD_WEB
    if [[ ! "$REBUILD_WEB" =~ ^[Yy]$ ]]; then
        BUILD_WEB=false
        echo "⏭  Skipping Flutter Web build."
    fi
fi

if [ "$BUILD_WEB" = true ]; then
    echo "Building Flutter Web..."
    (cd "$FRONTEND_DIR" && flutter build web --release)
    if [ $? -ne 0 ]; then
        echo "❌ ERROR: Flutter Web build failed."
        exit 1
    fi
    echo "✅ Flutter Web build done."
fi
echo ""

# --- Flutter APK ---
BUILD_APK=true
if [ -f "$APK_BUILD_PATH" ]; then
    read -p "Flutter APK already exists. Rebuild? (y/N): " REBUILD_APK
    if [[ ! "$REBUILD_APK" =~ ^[Yy]$ ]]; then
        BUILD_APK=false
        echo "⏭  Skipping Flutter APK build."
    fi
fi

if [ "$BUILD_APK" = true ]; then
    echo "Building Flutter APK (release)..."
    (cd "$FRONTEND_DIR" && flutter build apk --release)
    if [ $? -ne 0 ]; then
        echo "❌ ERROR: Flutter APK build failed."
        exit 1
    fi
    echo "✅ Flutter APK build done."
fi
echo ""

if [ "$UPLOAD" = true ]; then
    # --- Upload Flutter Web ---
    echo "Uploading Flutter Web to server..."
    ssh "$REMOTE_SERVER" "mkdir -p $REMOTE_PATH/invoice_app_frontend/build/web"
    rsync -avz --delete "$WEB_BUILD_DIR/" "$REMOTE_SERVER:$REMOTE_PATH/invoice_app_frontend/build/web/"
    if [ $? -ne 0 ]; then
        echo "❌ ERROR: Failed to upload Flutter Web build."
        exit 1
    fi
    echo "✅ Flutter Web uploaded."
    echo ""

    # --- Upload APK ---
    echo "Uploading Flutter APK to server..."
    ssh "$REMOTE_SERVER" "mkdir -p $REMOTE_PATH/invoice_app_frontend/build/app/outputs/apk/release"
    scp "$APK_BUILD_PATH" "$REMOTE_SERVER:$REMOTE_PATH/invoice_app_frontend/build/app/outputs/apk/release/app-release.apk"
    if [ $? -ne 0 ]; then
        echo "❌ ERROR: Failed to upload Flutter APK."
        exit 1
    fi
    echo "✅ Flutter APK uploaded."
    echo ""
    echo "--- Flutter build & upload complete! ---"
else
    echo "ℹ️  Local build only. Skipping upload step (REMOTE_SERVER and REMOTE_PATH not set)."
    echo "--- Flutter build complete! ---"
fi
