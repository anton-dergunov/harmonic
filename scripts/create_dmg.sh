#!/bin/bash
set -euo pipefail

VERSION="${1:?VERSION required}"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/Harmonic.app"
DMG_NAME="Harmonic-$VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

# Temporary DMG paths
TEMP_DMG="$BUILD_DIR/temp.dmg"
MOUNT_POINT="/Volumes/Harmonic"

# Clean up any previous DMG or mount point
rm -f "$DMG_PATH" "$TEMP_DMG"
if [[ -d "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" || true
fi

# Create a temporary DMG (150 MB)
hdiutil create -srcfolder "$APP_BUNDLE" -volname "Harmonic" -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW -size 150m "$TEMP_DMG"

# Mount the temporary DMG
hdiutil attach "$TEMP_DMG" -mountpoint "$MOUNT_POINT"

# Create symlink to Applications folder
ln -s /Applications "$MOUNT_POINT/Applications"

# Set custom icon and styling (optional)
# You can add a .background folder with a background image here if desired

# Unmount the DMG
hdiutil detach "$MOUNT_POINT"

# Convert to compressed format
hdiutil convert "$TEMP_DMG" -format UDZO -o "$DMG_PATH"

# Clean up temporary DMG
rm -f "$TEMP_DMG"

echo "✓ Created $DMG_PATH"
