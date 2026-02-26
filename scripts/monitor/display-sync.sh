#!/usr/bin/env bash
set -euo pipefail

# Keep a dummy HDMI display active only when the primary monitor is unavailable.
# This preserves normal high-refresh operation while still enabling Sunshine headless streaming.
PRIMARY_OUTPUT="DP-3"
DUMMY_OUTPUT="HDMI-A-1"
DEBUG="${DISPLAY_SYNC_DEBUG:-0}"
LAST_PRIMARY_STATE=""

log_debug() {
  if [[ "${DEBUG}" == "1" ]]; then
    printf '[display-sync] %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
  fi
}

is_primary_enabled() {
  local output
  local primary_block
  if [[ "${DEBUG}" == "1" ]]; then
    output="$(kscreen-doctor -o 2>&1 || true)"
  else
    output="$(kscreen-doctor -o 2>/dev/null || true)"
  fi

  primary_block="$(awk -v output_name="${PRIMARY_OUTPUT}" '
    /^Output:/ {
      if (in_block) {
        exit
      }
      if ($0 ~ ("(^|[[:space:]])" output_name "([[:space:]]|$)")) {
        in_block = 1
      }
    }
    in_block { print }
  ' <<<"${output}")"

  if [[ "${DEBUG}" == "1" ]]; then
    if [[ -n "${primary_block}" ]]; then
      log_debug "primary block found for ${PRIMARY_OUTPUT}"
    else
      log_debug "primary block not found for ${PRIMARY_OUTPUT}"
    fi
  fi

  [[ -n "${primary_block}" ]] && grep -qw "enabled" <<<"${primary_block}"
}

while true; do
  if is_primary_enabled; then
    primary_state="enabled"
    action="disable"
  else
    primary_state="not-enabled"
    action="enable"
  fi

  if [[ "${primary_state}" != "${LAST_PRIMARY_STATE}" ]]; then
    log_debug "primary ${PRIMARY_OUTPUT} is ${primary_state}; ${action} ${DUMMY_OUTPUT}"
    LAST_PRIMARY_STATE="${primary_state}"
  fi

  if [[ "${DEBUG}" == "1" ]]; then
    if ! kscreen-doctor "output.${DUMMY_OUTPUT}.${action}"; then
      log_debug "kscreen-doctor command failed: output.${DUMMY_OUTPUT}.${action}"
    fi
  else
    kscreen-doctor "output.${DUMMY_OUTPUT}.${action}" >/dev/null 2>&1 || true
  fi

  sleep 3
done
