#!/usr/bin/env bash
set -e

APP_DEST="${1:-$HOME/Desktop/Sync Keyboard Time.app}"
BIN_PATH="${2:-$HOME/.local/bin/rksync}"

echo "[*] Creating Desktop shortcut application: $APP_DEST"

TEMP_SCRIPT=$(mktemp /tmp/sync_app_XXXXXX.applescript)
cat << EOF > "$TEMP_SCRIPT"
try
    set output to do shell script "$BIN_PATH"
    display notification output with title "RK-S98 Keyboard" subtitle "Time Synchronized"
on error errMsg
    display notification errMsg with title "RK-S98 Keyboard" subtitle "Sync Failed"
end try
EOF

osacompile -o "$APP_DEST" "$TEMP_SCRIPT"
rm -f "$TEMP_SCRIPT"

echo "[+] Application created successfully at $APP_DEST"
