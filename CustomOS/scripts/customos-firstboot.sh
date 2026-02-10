#!/usr/bin/env bash
#
# customos-firstboot.sh
#
# Simple first-boot wizard for CustomOS.
# - Shows a welcome screen
# - Allows basic choices (Desktop/Server focus)
# - Can be extended later with more options
#
# This script is intended to be launched by an autostart .desktop file
# and will mark itself as "done" so it only runs once.

set -e
set -u
if set -o pipefail 2>/dev/null; then :; fi

STATE_DIR="/var/lib/customos"
STATE_FILE="${STATE_DIR}/firstboot_done"

LOG_TAG="CustomOS-FirstBoot"

log() {
  local level="$1"; shift
  echo "[$LOG_TAG][$level] $*" >&2
}

ensure_state_dir() {
  if [[ ! -d "$STATE_DIR" ]]; then
    mkdir -p "$STATE_DIR"
    chmod 755 "$STATE_DIR"
  fi
}

mark_done() {
  ensure_state_dir
  date >"$STATE_FILE" 2>/dev/null || true
}

is_done() {
  [[ -f "$STATE_FILE" ]]
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

run_zenity_wizard() {
  # Basic welcome + mode choice; can be made richer later.
  local result

  if ! has_command zenity; then
    return 1
  fi

  result="$(
    zenity --forms \
      --title="Welcome to CustomOS" \
      --text="Deep Sea Dark - CustomOS setup" \
      --add-combo="Preferred mode" --combo-values="Desktop-focused|Server-focused" \
      --add-combo="Enable Guardian on boot" --combo-values="Yes|No" \
      --separator='|' 2>/dev/null || true
  )"

  if [[ -z "$result" ]]; then
    # User cancelled
    return 0
  fi

  IFS='|' read -r preferred_mode guardian_boot <<<"$result"

  # Mode choice is currently mostly informational; could be wired into
  # default targets later. For now we just log it.
  log "INFO" "Firstboot choice: preferred_mode=$preferred_mode guardian_boot=$guardian_boot"

  if [[ "$guardian_boot" == "No" ]]; then
    # User does not want Guardian; disable service if present
    if has_command systemctl; then
      systemctl disable customos-guardian.service >/dev/null 2>&1 || true
      systemctl stop customos-guardian.service >/dev/null 2>&1 || true
    fi
  fi

  zenity --info \
    --title="CustomOS Ready" \
    --text=$'CustomOS is ready.\n\nYou can switch modes with:\n  sudo customos --desktop\n  sudo customos --server\n\nEnjoy your Deep Sea Dark desktop.' \
    2>/dev/null || true
}

run_tty_wizard() {
  cat <<'EOF'
Welcome to CustomOS (Deep Sea Dark)

Basic commands:
  sudo customos --status    # Check current mode
  sudo customos --desktop   # Start Desktop mode
  sudo customos --server    # Switch to Server mode
  guardian --check          # System health check

You can change these later in configuration. This first-boot helper
will not run again.
EOF
}

main() {
  if is_done; then
    exit 0
  fi

  ensure_state_dir

  # Prefer a small GUI wizard if a display is available.
  if [[ -n "${DISPLAY:-}" ]]; then
    run_zenity_wizard || run_tty_wizard
  else
    run_tty_wizard
  fi

  mark_done
}

main "$@"

