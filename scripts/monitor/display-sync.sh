#!/usr/bin/env bash
set -euo pipefail

# Keep a dummy HDMI display active only when the primary monitor is unavailable.
# This preserves normal high-refresh operation while still enabling Sunshine headless streaming.
PRIMARY_OUTPUT="DP-3"
DUMMY_OUTPUT="HDMI-A-1"

is_primary_enabled() {
  local output
  output="$(kscreen-doctor -o 2>/dev/null || true)"
  grep -qE "Output:.*[[:space:]]${PRIMARY_OUTPUT}[[:space:]].*\\benabled\\b" <<<"${output}"
}

while true; do
  if is_primary_enabled; then
    kscreen-doctor "output.${DUMMY_OUTPUT}.disable" >/dev/null 2>&1 || true
  else
    kscreen-doctor "output.${DUMMY_OUTPUT}.enable" >/dev/null 2>&1 || true
  fi

  sleep 3
done
