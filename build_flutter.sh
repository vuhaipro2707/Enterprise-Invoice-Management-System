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

# --- Clean & Build confirmation ---
read -p "Clean build cache and rebuild everything? (y/N): " CONFIRM_BUILD
echo ""

if [[ ! "$CONFIRM_BUILD" =~ ^[Yy]$ ]]; then
    echo "⏭  Skipping build and upload."
    exit 0
fi

echo "🧹 Cleaning Flutter build cache..."
(cd "$FRONTEND_DIR" && flutter clean && flutter pub get)
if [ $? -ne 0 ]; then
    echo "❌ ERROR: Flutter clean/pub get failed."
    exit 1
fi
echo "✅ Clean complete."
echo ""

# --- Flutter Web ---
echo "Building Flutter Web..."
(cd "$FRONTEND_DIR" && flutter build web --release)
if [ $? -ne 0 ]; then
    echo "❌ ERROR: Flutter Web build failed."
    exit 1
fi
echo "✅ Flutter Web build done."
echo ""

# --- Flutter APK ---
echo "Building Flutter APK (release)..."
(cd "$FRONTEND_DIR" && flutter build apk --release)
if [ $? -ne 0 ]; then
    echo "❌ ERROR: Flutter APK build failed."
    exit 1
fi
echo "✅ Flutter APK build done."
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
    ssh "$REMOTE_SERVER" "mkdir -p $REMOTE_PATH/invoice_app_frontend/build/app/outputs/flutter-apk"
    scp "$APK_BUILD_PATH" "$REMOTE_SERVER:$REMOTE_PATH/invoice_app_frontend/build/app/outputs/flutter-apk/app-release.apk"
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
