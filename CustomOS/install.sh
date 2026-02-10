#!/usr/bin/env bash
#
# CustomOS v1.0 installer
#
# Tested target: Debian/Ubuntu minimal base.
# Run with:
#   sudo bash install.sh
#

set -euo pipefail

LOG_TAG="CustomOS-Install"

log() {
  local level="$1"; shift
  echo "[$LOG_TAG][$level] $*" >&2
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log "ERROR" "This script must be run as root (use sudo)."
    exit 1
  fi
}

detect_apt() {
  if ! command -v apt-get >/dev/null 2>&1; then
    log "ERROR" "apt-get not found. This installer targets Debian/Ubuntu."
    exit 1
  fi
}

install_base_packages() {
  log "INFO" "Updating apt package lists..."
  apt-get update -y

  log "INFO" "Installing core packages (XFCE, LightDM, Flatpak, Wine, Docker, Python)..."
  # Core desktop + DM
  apt-get install -y \
    xfce4 xfce4-goodies lightdm lightdm-gtk-greeter \
    flatpak \
    wine winetricks \
    docker.io \
    samba \
    python3 python3-venv python3-pip \
    curl git || log "WARN" "Some packages failed to install (check above)."

  # Optional: lightweight browser (you can change later)
  log "INFO" "Installing lightweight browser (Firefox ESR)..."
  apt-get install -y firefox-esr || log "WARN" "Failed to install firefox-esr."
}

setup_directories() {
  log "INFO" "Creating CustomOS directories..."
  install -d /opt/customos/scripts
  install -d /opt/customos/scripts/ai
  install -d /opt/customos/ui/themes/deep-sea-dark/gtk-3.0
}

copy_scripts() {
  local src_root
  src_root="$(pwd)"

  log "INFO" "Copying scripts..."
  install -m 0755 "$src_root/scripts/customos-switch.sh" /usr/local/bin/customos
  install -m 0755 "$src_root/scripts/guardian.sh" /usr/local/bin/guardian

  install -m 0644 "$src_root/scripts/ai/ollama_client.py" /opt/customos/scripts/ai/ollama_client.py
}

install_theme() {
  local src_root
  src_root="$(pwd)"

  log "INFO" "Installing Deep Sea Dark GTK theme (user-wide template)..."

  if [[ -f "$src_root/ui/themes/deep-sea-dark/gtk-3.0/gtk.css" ]]; then
    install -m 0644 "$src_root/ui/themes/deep-sea-dark/gtk-3.0/gtk.css" \
      /opt/customos/ui/themes/deep-sea-dark/gtk-3.0/gtk.css
  else
    log "WARN" "Deep Sea Dark GTK theme source not found."
  fi

  # Copy also to /usr/share/themes so XFCE can pick it up
  install -d /usr/share/themes/Deep-Sea-Dark/gtk-3.0
  if [[ -f /opt/customos/ui/themes/deep-sea-dark/gtk-3.0/gtk.css ]]; then
    install -m 0644 /opt/customos/ui/themes/deep-sea-dark/gtk-3.0/gtk.css \
      /usr/share/themes/Deep-Sea-Dark/gtk-3.0/gtk.css
  fi
}

install_systemd_units() {
  local src_root
  src_root="$(pwd)"

  log "INFO" "Installing systemd service for Guardian..."

  cat >/etc/systemd/system/customos-guardian.service <<'EOF'
[Unit]
Description=CustomOS Guardian (Local AI system monitor)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/guardian --watch
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable customos-guardian.service || log "WARN" "Failed to enable customos-guardian.service."
}

print_summary() {
  cat <<'EOF'

CustomOS v1.0 installation complete (base).

You can now test:

  # Check modes
  sudo customos --status

  # Switch to server mode (no GUI, keep services)
  sudo customos --server

  # Switch back to desktop mode
  sudo customos --desktop

  # Run Guardian once
  guardian --check

Notes:
  - Ensure Jellyfin/Plex/Samba are installed/configured if you want full Server mode benefits.
  - For local AI (Ollama), install Ollama separately and configure models; Guardian will try to call it.

EOF
}

main() {
  require_root
  detect_apt
  install_base_packages
  setup_directories
  copy_scripts
  install_theme
  install_systemd_units
  print_summary
}

main "$@"

