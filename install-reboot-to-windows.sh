#!/usr/bin/env bash
set -euo pipefail

# Fedora: setup "Reboot to Windows" launcher (script + .desktop + icon)

BIN_DIR="$HOME/.local/bin"
ICON_DIR="$HOME/.local/share/icons"
APP_DIR="$HOME/.local/share/applications"

ICON_PATH="$ICON_DIR/windows.svg"
REBOOT_SCRIPT="$BIN_DIR/reboot-to-windows.sh"
DESKTOP_ENTRY="$APP_DIR/reboot-to-windows.desktop"

WIN_ICON_URL="https://upload.wikimedia.org/wikipedia/commons/6/6a/Windows_logo_-_2021_%28White%29.svg"

mkdir -p "$BIN_DIR" "$ICON_DIR" "$APP_DIR"

# Download Windows icon
if command -v curl >/dev/null 2>&1; then
  curl -fL -o "$ICON_PATH" "$WIN_ICON_URL"
else
  echo "ERROR: curl not found" >&2
  exit 1
fi

# Find Windows Boot Manager EFI boot ID (e.g. 0000)
if ! command -v efibootmgr >/dev/null 2>&1; then
  echo "ERROR: efibootmgr not found. Install it: sudo dnf install -y efibootmgr" >&2
  exit 1
fi

# efibootmgr needs root, so use sudo for the probe
WIN_BOOT_ID="$(sudo efibootmgr 2>/dev/null | awk -F'[* ]+' '/^Boot[0-9A-Fa-f]{4}\*?[[:space:]]+Windows Boot Manager/ {print substr($1,5,4); exit}')"

if [[ -z "${WIN_BOOT_ID:-}" ]]; then
  echo "ERROR: Could not find 'Windows Boot Manager' in efibootmgr output." >&2
  echo "Run: sudo efibootmgr" >&2
  exit 1
fi

# Create reboot script
cat > "$REBOOT_SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

WIN_BOOT_ID="${WIN_BOOT_ID:-}"

if [[ -z "$WIN_BOOT_ID" ]]; then
  echo "ERROR: WIN_BOOT_ID not set" >&2
  exit 1
fi

# GUI confirm (prefer kdialog, then zenity). If neither exists, refuse.
confirm() {
  local msg="Reboot into Windows now?"
  if command -v kdialog >/dev/null 2>&1; then
    kdialog --title "Reboot to Windows" --warningyesno "$msg"
    return $?
  fi
  if command -v zenity >/dev/null 2>&1; then
    zenity --question --title="Reboot to Windows" --text="$msg"
    return $?
  fi
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "Reboot to Windows" "Install kdialog or zenity for confirmation prompts."
  fi
  echo "ERROR: Need kdialog or zenity for a Yes/No popup." >&2
  return 2
}

confirm || exit 0

# Need root for efibootmgr + reboot.
# Prefer pkexec if available (nice GUI auth), otherwise sudo.
run_root() {
  if command -v pkexec >/dev/null 2>&1; then
    pkexec "$@"
  else
    sudo "$@"
  fi
}

run_root efibootmgr -n "$WIN_BOOT_ID"
run_root systemctl reboot
EOF

# Inject the discovered boot id after the shebang.
# Keep shebang on line 1 so desktop launchers can execute the script directly.
tmp="$(mktemp)"
{
  head -n 1 "$REBOOT_SCRIPT"
  echo "WIN_BOOT_ID=\"$WIN_BOOT_ID\""
  tail -n +2 "$REBOOT_SCRIPT"
} > "$tmp"
mv "$tmp" "$REBOOT_SCRIPT"
chmod +x "$REBOOT_SCRIPT"

# Create .desktop entry
cat > "$DESKTOP_ENTRY" <<EOF
[Desktop Entry]
Type=Application
Name=Reboot to Windows
Comment=Set UEFI BootNext to Windows Boot Manager and reboot
Exec=$REBOOT_SCRIPT
Icon=$ICON_PATH
Terminal=false
Categories=System;
EOF

chmod 0644 "$DESKTOP_ENTRY"

echo "OK:"
echo "- Icon:    $ICON_PATH"
echo "- Script:  $REBOOT_SCRIPT (Windows Boot ID: $WIN_BOOT_ID)"
echo "- Desktop: $DESKTOP_ENTRY"
echo
echo "Next: add it to KDE panel (Application Launcher, or pin from menu), or put it on the desktop."
