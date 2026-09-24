#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$HOME/.local/bin"
PLIST_SRC="$DIR/LaunchAgent/com.user.rks98timesync.plist"
PLIST_DEST="$HOME/Library/LaunchAgents/com.user.rks98timesync.plist"

mkdir -p "$BIN_DIR"
mkdir -p "$HOME/Library/LaunchAgents"

echo "[*] Compiling native Swift binary (rksync)..."
swiftc -O "$DIR/Sources/rksync.swift" -o "$BIN_DIR/rksync"
chmod +x "$BIN_DIR/rksync"
echo "[+] Binary installed to $BIN_DIR/rksync"

echo "[*] Copying Python script..."
cp "$DIR/Sources/rk_s98_sync.py" "$BIN_DIR/rk_s98_sync.py"
chmod +x "$BIN_DIR/rk_s98_sync.py"

echo "[*] Creating Desktop one-click app..."
"$DIR/Scripts/create_app.sh" "$HOME/Desktop/Sync Keyboard Time.app" "$BIN_DIR/rksync"

echo "[*] Installing LaunchAgent..."
launchctl unload "$PLIST_DEST" 2>/dev/null || true
sed "s|__BIN_PATH__|$BIN_DIR/rksync|g" "$PLIST_SRC" > "$PLIST_DEST"
launchctl load "$PLIST_DEST"

echo ""
echo "============================================================"
echo " [SUCCESS] RK-S98 Mac Time Sync Installed!"
echo "============================================================"
echo " - Desktop app : ~/Desktop/Sync Keyboard Time.app"
echo " - CLI binary  : rksync (in ~/.local/bin)"
echo " - Background  : LaunchAgent loaded"
echo ""
echo "Note on Background Daemon:"
echo " If you want the background daemon to run without user clicks,"
echo " grant Input Monitoring permission to:"
echo "   $BIN_DIR/rksync"
echo " in System Settings -> Privacy & Security -> Input Monitoring."
echo "============================================================"
