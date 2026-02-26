#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="${SCRIPT_DIR}/display-sync.sh"
TARGET_BIN_DIR="${HOME}/.local/bin"
TARGET_SCRIPT="${TARGET_BIN_DIR}/display-sync.sh"
SYSTEMD_USER_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${SYSTEMD_USER_DIR}/display-sync.service"

mkdir -p "${TARGET_BIN_DIR}" "${SYSTEMD_USER_DIR}"
install -m 0755 "${SOURCE_SCRIPT}" "${TARGET_SCRIPT}"

cat >"${SERVICE_FILE}" <<'EOF'
[Unit]
Description=Auto toggle dummy display based on primary state
After=graphical-session.target

[Service]
ExecStart=%h/.local/bin/display-sync.sh
Restart=always

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now display-sync.service

echo "display-sync installed and started."
echo "Check status with: systemctl --user status display-sync.service"
