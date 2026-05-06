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
cp "$APP_DIR/pubspec.yaml" "$BACKUP_DIR/pubspec.yaml"
cp "$APP_DIR/.gitignore" "$BACKUP_DIR/.gitignore" 2>/dev/null || true
# Also preserve our customised AndroidManifest.xml
cp "$APP_DIR/android/app/src/main/AndroidManifest.xml" "$BACKUP_DIR/AndroidManifest.xml" 2>/dev/null || true

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

echo "==> Merging pubspec.yaml dependencies …"
python3 - <<PYEOF
import yaml, os

app_dir = "$APP_DIR"
backup_dir = "$BACKUP_DIR"

with open(f"{app_dir}/pubspec.yaml") as f:
    generated = yaml.safe_load(f)

with open(f"{backup_dir}/pubspec.yaml") as f:
    custom = yaml.safe_load(f)

# Merge dependencies (keep generated flutter/cupertino_icons, add ours)
generated.setdefault("dependencies", {}).update(
    {k: v for k, v in custom.get("dependencies", {}).items()
     if k not in ("flutter",)}
)

with open(f"{app_dir}/pubspec.yaml", "w") as f:
    yaml.dump(generated, f, default_flow_style=False, allow_unicode=True)

print("pubspec.yaml merged OK")
PYEOF

echo "==> Restoring .gitignore …"
cp "$BACKUP_DIR/.gitignore" "$APP_DIR/.gitignore" 2>/dev/null || true

echo "==> Restoring customised AndroidManifest.xml …"
if [ -f "$BACKUP_DIR/AndroidManifest.xml" ]; then
  cp "$BACKUP_DIR/AndroidManifest.xml" \
     "$APP_DIR/android/app/src/main/AndroidManifest.xml"
fi

echo "==> Cleaning up backup …"
rm -rf "$BACKUP_DIR"

echo ""
echo "✅ Done! Now run:"
echo "   cd android_app && flutter pub get && flutter build apk --release"
