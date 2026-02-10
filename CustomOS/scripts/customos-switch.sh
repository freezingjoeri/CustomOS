#!/usr/bin/env bash
#
# customos-switch.sh
#
# Core mode switcher for CustomOS:
#   - Desktop mode: Full GUI, apps, browser.
#   - Server mode : No X/DM, only core services (Docker, Jellyfin, Plex, Samba).
#
# Intended install path: /usr/local/bin/customos
# Usage:
#   customos --desktop
#   customos --server
#   customos --status
#

set -euo pipefail

# ------------- CONFIGURATION --------------

# Known display managers – customize for your spin
DISPLAY_MANAGERS=("lightdm" "gdm3" "sddm" "lxdm")

# Core service list that should stay up in Server mode
SERVER_SERVICES=("docker" "jellyfin" "plexmediaserver" "smbd" "nmbd")

# Optional: services that are Desktop-only
DESKTOP_ONLY_SERVICES=()

LOG_TAG="CustomOS-Switch"

# ------------- HELPER FUNCTIONS ----------

log() {
    # Log to stderr and to system logger if available
    local level="$1"; shift
    local msg="$*"
    echo "[$LOG_TAG][$level] $msg" >&2
    if command -v logger >/dev/null 2>&1; then
        logger -t "$LOG_TAG" "[$level] $msg"
    fi
}

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        log "ERROR" "This command must be run as root (use sudo)."
        exit 1
    fi
}

detect_active_dm() {
    # Try to detect which display manager is active/enabled.
    for dm in "${DISPLAY_MANAGERS[@]}"; do
        if systemctl is-enabled "$dm" >/dev/null 2>&1 || \
           systemctl is-active "$dm"  >/dev/null 2>&1; then
            echo "$dm"
            return 0
        fi
    done
    return 1
}

stop_display_stack() {
    log "INFO" "Stopping graphical target and display manager (Server mode)."

    # Stop graphical.target if present
    if systemctl list-units --type=target | grep -q "graphical.target"; then
        systemctl stop graphical.target || log "WARN" "Failed to stop graphical.target"
    fi

    # Stop any known display manager
    local dm
    dm="$(detect_active_dm || true)" || true
    if [[ -n "${dm:-}" ]]; then
        log "INFO" "Stopping display manager: $dm"
        systemctl stop "$dm" || log "WARN" "Failed to stop $dm"
    else
        log "INFO" "No active display manager detected."
    fi

    # Kill residual X sessions (best-effort)
    if pgrep -x Xorg >/dev/null 2>&1; then
        log "INFO" "Killing remaining Xorg processes."
        pkill -15 Xorg || true
        sleep 2
        pkill -9 Xorg || true
    fi
}

start_display_stack() {
    log "INFO" "Starting graphical target and display manager (Desktop mode)."

    local dm
    dm="$(detect_active_dm || true)" || true

    if [[ -n "${dm:-}" ]]; then
        log "INFO" "Starting display manager: $dm"
        systemctl start "$dm" || log "WARN" "Failed to start $dm"
    else
        # If no DM detected, try enabling lightdm by default (can be customized)
        if command -v lightdm >/dev/null 2>&1; then
            log "INFO" "Enabling and starting lightdm as default display manager."
            systemctl enable lightdm || true
            systemctl start lightdm  || log "WARN" "Failed to start lightdm"
        else
            log "ERROR" "No display manager found. Install one (e.g. lightdm, gdm3, sddm)."
            return 1
        fi
    fi

    # Ensure graphical.target is up
    if systemctl list-units --type=target | grep -q "graphical.target"; then
        systemctl start graphical.target || log "WARN" "Failed to start graphical.target"
    fi
}

ensure_server_services() {
    log "INFO" "Ensuring core server services are running."
    for svc in "${SERVER_SERVICES[@]}"; do
        if systemctl list-unit-files | grep -q "^${svc}\.service"; then
            log "INFO" "Starting service: $svc"
            systemctl start "$svc" || log "WARN" "Failed to start $svc"
            systemctl enable "$svc" || true
        else
            log "WARN" "Service not installed/known: $svc"
        fi
    done
}

stop_desktop_only_services() {
    if [[ "${#DESKTOP_ONLY_SERVICES[@]}" -eq 0 ]]; then
        return 0
    fi
    log "INFO" "Stopping desktop-only services."
    for svc in "${DESKTOP_ONLY_SERVICES[@]}"; do
        if systemctl list-unit-files | grep -q "^${svc}\.service"; then
            log "INFO" "Stopping desktop service: $svc"
            systemctl stop "$svc" || log "WARN" "Failed to stop $svc"
        fi
    done
}

# ------------- MODE ACTIONS --------------

enter_server_mode() {
    require_root
    log "INFO" "Switching to SERVER mode."

    stop_display_stack
    stop_desktop_only_services
    ensure_server_services

    log "INFO" "System is now in SERVER mode (no GUI; core services running)."
}

enter_desktop_mode() {
    require_root
    log "INFO" "Switching to DESKTOP mode."

    # Ensure server services are still up unless explicitly disabled.
    ensure_server_services
    start_display_stack

    log "INFO" "System is now in DESKTOP mode (GUI enabled)."
}

show_status() {
    echo "== CustomOS Mode Status =="

    if systemctl is-active graphical.target >/dev/null 2>&1; then
        echo "Mode: DESKTOP (graphical.target is active)"
    else
        echo "Mode: SERVER (graphical.target is inactive)"
    fi

    echo
    echo "Display manager status:"
    for dm in "${DISPLAY_MANAGERS[@]}"; do
        if systemctl list-unit-files | grep -q "^${dm}\.service"; then
            printf "  %-10s: %s\n" "$dm" "$(systemctl is-active "$dm" 2>/dev/null || echo unknown)"
        fi
    done

    echo
    echo "Core server services:"
    for svc in "${SERVER_SERVICES[@]}"; do
        if systemctl list-unit-files | grep -q "^${svc}\.service"; then
            printf "  %-16s: %s\n" "$svc" "$(systemctl is-active "$svc" 2>/dev/null || echo unknown)"
        else
            printf "  %-16s: not installed\n" "$svc"
        fi
    done
}

print_help() {
    cat <<EOF
CustomOS Mode Switcher

Usage:
  customos --desktop     Switch to Desktop mode (start GUI/display manager).
  customos --server      Switch to Server mode (stop GUI, keep core services).
  customos --status      Show current mode and service status.
  customos --help        Show this help.

Notes:
  - Must be run as root (use sudo).
  - SERVER_SERVICES and DISPLAY_MANAGERS are configured at top of script.
EOF
}

# ------------- ARGUMENT PARSING ----------

if [[ $# -lt 1 ]]; then
    print_help
    exit 1
fi

case "$1" in
    --desktop)
        enter_desktop_mode
        ;;
    --server)
        enter_server_mode
        ;;
    --status)
        show_status
        ;;
    --help|-h)
        print_help
        ;;
    *)
        log "ERROR" "Unknown argument: $1"
        print_help
        exit 1
        ;;
esac

