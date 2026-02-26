#!/usr/bin/env bash
set -euo pipefail

log() { printf '%s\n' "[mangohud-setup] $*"; }

# 1) Install packages (RPM)
log "Installing packages (mangohud, gamemode)..."
sudo dnf5 install -y mangohud gamemode

# 2) Create config
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/MangoHud"
CONF_FILE="${CONF_DIR}/MangoHud.conf"
mkdir -p "$CONF_DIR"

if [[ -f "$CONF_FILE" ]]; then
  ts="$(date +%Y%m%d-%H%M%S)"
  backup="${CONF_FILE}.bak.${ts}"
  log "Backing up existing config to: $backup"
  cp -a "$CONF_FILE" "$backup"
fi

log "Writing MangoHud config to: $CONF_FILE"
cat >"$CONF_FILE" <<'EOF'
# MangoHud config
# Toggle overlay on/off
toggle_hud=F10

# Optional: toggle logging (handy sometimes)
toggle_logging=F11

# Keep it lightweight: comment these in/out as you like
# fps
# frametime
# gpu_stats
# cpu_stats
# ram
# vram
EOF

log "Done."
log "Usage:"
log "  - Steam launch option: MANGOHUD=1 %command%"
log "  - Toggle in-game: F10"