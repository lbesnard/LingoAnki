#!/usr/bin/env bash
# Run this script from the repo root to regenerate the Flutter project
# with the proper Gradle scaffolding, then restore custom source files.
#
# Usage:  bash scripts/setup_flutter_app.sh
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO_ROOT/android_app"
BACKUP_DIR="$REPO_ROOT/.android_app_src_backup"

echo "==> Backing up custom lib/ and pubspec.yaml …"
rm -rf "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR"
cp -r "$APP_DIR/lib" "$BACKUP_DIR/"
cp -r "$APP_DIR/test" "$BACKUP_DIR/" 2>/dev/null || true
cp "$APP_DIR/pubspec.yaml" "$BACKUP_DIR/pubspec.yaml"
cp "$APP_DIR/.gitignore" "$BACKUP_DIR/.gitignore" 2>/dev/null || true
# Also preserve our customised AndroidManifest.xml
cp "$APP_DIR/android/app/src/main/AndroidManifest.xml" "$BACKUP_DIR/AndroidManifest.xml" 2>/dev/null || true
cp "$APP_DIR/android/app/build.gradle.kts" "$BACKUP_DIR/build.gradle.kts" 2>/dev/null || true
cp "$APP_DIR/android/build.gradle.kts" "$BACKUP_DIR/root_build.gradle.kts" 2>/dev/null || true
cp "$APP_DIR/android/settings.gradle.kts" "$BACKUP_DIR/settings.gradle.kts" 2>/dev/null || true

echo "==> Removing old android_app/ …"
rm -rf "$APP_DIR"

echo "==> Running flutter create …"
flutter create \
  --org com.lingodiary \
  --project-name lingodiary_app \
  --platforms android \
  "$APP_DIR"

echo "==> Restoring custom lib/ …"
rm -rf "$APP_DIR/lib"
cp -r "$BACKUP_DIR/lib" "$APP_DIR/lib"

echo "==> Restoring custom test/ …"
rm -rf "$APP_DIR/test"
cp -r "$BACKUP_DIR/test" "$APP_DIR/test" 2>/dev/null || true

echo "==> Restoring pubspec.yaml …"
cp "$BACKUP_DIR/pubspec.yaml" "$APP_DIR/pubspec.yaml"
echo "pubspec.yaml restored OK"

echo "==> Restoring .gitignore …"
cp "$BACKUP_DIR/.gitignore" "$APP_DIR/.gitignore" 2>/dev/null || true

echo "==> Restoring customised AndroidManifest.xml …"
if [ -f "$BACKUP_DIR/AndroidManifest.xml" ]; then
  cp "$BACKUP_DIR/AndroidManifest.xml" \
    "$APP_DIR/android/app/src/main/AndroidManifest.xml"
fi

echo "==> Restoring customised app/build.gradle.kts …"
if [ -f "$BACKUP_DIR/build.gradle.kts" ]; then
  cp "$BACKUP_DIR/build.gradle.kts" \
    "$APP_DIR/android/app/build.gradle.kts"
fi

if [ -f "$BACKUP_DIR/root_build.gradle.kts" ]; then
  cp "$BACKUP_DIR/root_build.gradle.kts" "$APP_DIR/android/build.gradle.kts"
fi
if [ -f "$BACKUP_DIR/settings.gradle.kts" ]; then
  cp "$BACKUP_DIR/settings.gradle.kts" "$APP_DIR/android/settings.gradle.kts"
fi

echo "==> Cleaning up backup …"
rm -rf "$BACKUP_DIR"

echo ""
echo "✅ Done! Now run:"
echo "   cd android_app && flutter clean && flutter pub get && flutter build apk --release"
