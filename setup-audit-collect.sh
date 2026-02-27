#!/usr/bin/env bash
set -euo pipefail

# setup-audit: capture mutable Fedora state for rebuild reproducibility
# Writes into: setup-audit/state/

OUT_DIR="setup-audit/state"

mkdir -p "$OUT_DIR"

log() { printf '%s\n' "==> $*"; }

run_to_file() {
  local outfile="$1"
  shift
  # shellcheck disable=SC2124
  local cmd="$*"
  log "$cmd"
  # Capture both stdout+stderr, but keep exit code visible in file if it fails.
  if "$@" >"$outfile" 2>&1; then
    :
  else
    local rc=$?
    {
      echo
      echo "COMMAND FAILED (exit=$rc): $cmd"
    } >>"$outfile"
  fi
}

append_line_file() {
  local outfile="$1"
  shift
  printf '%s\n' "$*" >>"$outfile"
}

log "Collecting system info…"

# Basic host identity (helps when diffing across installs)
run_to_file "$OUT_DIR/uname.txt" uname -a
run_to_file "$OUT_DIR/os-release.txt" bash -lc 'cat /etc/os-release'
run_to_file "$OUT_DIR/hostnamectl.txt" hostnamectl
run_to_file "$OUT_DIR/lsblk.txt" lsblk -f
run_to_file "$OUT_DIR/findmnt-root.txt" findmnt /
run_to_file "$OUT_DIR/fstab.txt" bash -lc 'cat /etc/fstab'

# Packages
run_to_file "$OUT_DIR/rpm-all.txt" rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n'
run_to_file "$OUT_DIR/dnf-userinstalled.txt" bash -lc 'dnf -qy repoquery --userinstalled --qf "%{name}" | sort -u'
run_to_file "$OUT_DIR/dnf-enabled-repos.txt" bash -lc 'dnf repolist --enabled'

# Boot / kernel args (BLS + grubby + cmdline)
run_to_file "$OUT_DIR/proc-cmdline.txt" bash -lc 'cat /proc/cmdline'
run_to_file "$OUT_DIR/grubby-all.txt" bash -lc 'command -v grubby >/dev/null && grubby --info=ALL || echo "grubby not found"'
run_to_file "$OUT_DIR/kernel-cmdline.txt" bash -lc 'test -f /etc/kernel/cmdline && cat /etc/kernel/cmdline || echo "/etc/kernel/cmdline not present"'

# Keep a copy of /etc/default/grub if present
if [[ -f /etc/default/grub ]]; then
  log "Copying /etc/default/grub"
  cp -a /etc/default/grub "$OUT_DIR/etc-default-grub"
else
  log "/etc/default/grub not present"
  : >"$OUT_DIR/etc-default-grub"
  echo "missing" >"$OUT_DIR/etc-default-grub"
fi

# EFI
run_to_file "$OUT_DIR/efibootmgr.txt" bash -lc 'command -v efibootmgr >/dev/null && sudo efibootmgr -v || echo "efibootmgr not found"'

# systemd enabled units (system scope)
run_to_file "$OUT_DIR/systemd-enabled-system.txt" bash -lc 'systemctl list-unit-files --state=enabled --no-pager'
run_to_file "$OUT_DIR/systemd-enabled-system-services.txt" bash -lc 'systemctl list-unit-files --type=service --state=enabled --no-pager'

# systemd enabled user units (for *current user*); try to work both locally and over SSH
# If user manager isn't running, this will fail gracefully and record the failure.
run_to_file "$OUT_DIR/systemd-enabled-user.txt" bash -lc 'systemctl --user list-unit-files --state=enabled --no-pager'

# Btrfs + snapper state (critical for your snapper sanity later)
run_to_file "$OUT_DIR/btrfs-subvolumes.txt" bash -lc 'sudo btrfs subvolume list -t /'
run_to_file "$OUT_DIR/btrfs-default-subvol.txt" bash -lc 'sudo btrfs subvolume get-default /'
run_to_file "$OUT_DIR/btrfs-df.txt" bash -lc 'sudo btrfs filesystem df /'
run_to_file "$OUT_DIR/btrfs-show.txt" bash -lc 'sudo btrfs filesystem show'

run_to_file "$OUT_DIR/snapper-configs.txt" bash -lc 'command -v snapper >/dev/null && sudo snapper list-configs || echo "snapper not found"'
run_to_file "$OUT_DIR/snapper-root-config.txt" bash -lc 'command -v snapper >/dev/null && sudo snapper -c root get-config || echo "snapper not found or no root config"'
run_to_file "$OUT_DIR/snapper-root-list.txt" bash -lc 'command -v snapper >/dev/null && sudo snapper -c root list || echo "snapper not found or no root config"'

# Secure Boot + MOK + Nvidia-ish state
run_to_file "$OUT_DIR/secureboot.txt" bash -lc 'command -v mokutil >/dev/null && sudo mokutil --sb-state || echo "mokutil not found"'
run_to_file "$OUT_DIR/mokutil-list-enrolled.txt" bash -lc 'command -v mokutil >/dev/null && sudo mokutil --list-enrolled || echo "mokutil not found"'
run_to_file "$OUT_DIR/akmods-certs.txt" bash -lc 'sudo ls -l /etc/pki/akmods/certs 2>&1 || true'
run_to_file "$OUT_DIR/lsmod-nvidia.txt" bash -lc 'lsmod | grep -i nvidia || true'

# Display/session hints (helpful for Wayland/X11 debugging)
run_to_file "$OUT_DIR/session-type.txt" bash -lc 'echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-}"'
run_to_file "$OUT_DIR/loginctl-sessions.txt" bash -lc 'loginctl list-sessions --no-pager'
run_to_file "$OUT_DIR/loginctl-users.txt" bash -lc 'loginctl list-users --no-pager'

# Network snapshot (for SSH sanity)
run_to_file "$OUT_DIR/nm-connections.txt" bash -lc 'command -v nmcli >/dev/null && nmcli connection show || echo "nmcli not found"'
run_to_file "$OUT_DIR/ip-addr.txt" ip addr
run_to_file "$OUT_DIR/sshd-status.txt" bash -lc 'systemctl status sshd --no-pager -l'

# GUI stack bits (optional but useful)
run_to_file "$OUT_DIR/plasma-packages.txt" bash -lc 'rpm -qa | grep -iE "plasma|kwin|kde" | sort || true'
run_to_file "$OUT_DIR/boot-time.txt" bash -lc 'systemd-analyze time'
run_to_file "$OUT_DIR/boot-blame-top50.txt" bash -lc 'systemd-analyze blame | head -n 50'
run_to_file "$OUT_DIR/boot-critical-chain.txt" bash -lc 'systemd-analyze critical-chain --no-pager'

log "Done. Wrote: $OUT_DIR"
log "Next: git add setup-audit/state && commit, unless you enjoy losing work."
