#!/usr/bin/env bash
set -e

if [ -n "$1" ]; then
    APP_DEST="$1"
elif [ -w "/Applications" ]; then
    APP_DEST="/Applications/Sync Keyboard Time.app"
else
    APP_DEST="$HOME/Applications/Sync Keyboard Time.app"
fi
BIN_PATH="${2:-$HOME/.local/bin/rksync}"

echo "[*] Creating macOS application at: $APP_DEST"
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
