#!/usr/bin/env bash
#
# guardian.sh
#
# CustomOS "Guardian" system monitor with optional local AI (Ollama) integration.
# Can be run on-demand from terminal or as a background watcher (systemd service).
#
# Usage:
#   guardian --check       # One-off health check, human-readable
#   guardian --json        # One-off health check, JSON
#   guardian --watch       # Run as daemon, periodically log + AI analysis
#

set -euo pipefail

LOG_TAG="CustomOS-Guardian"
AI_CLIENT="/opt/customos/scripts/ai/ollama_client.py"
CHECK_INTERVAL_SECONDS=60

log() {
  local level="$1"; shift
  echo "[$LOG_TAG][$level] $*" >&2
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

collect_metrics_json() {
  # CPU load
  local load1 load5 load15
  read -r load1 load5 load15 _ < <(awk '{print $1, $2, $3, $4}' /proc/loadavg)

  # Memory (MiB)
  local mem_total mem_used mem_free
  read -r _ mem_total _ < <(grep -i MemTotal /proc/meminfo || echo "MemTotal: 0 kB")
  read -r _ mem_free _  < <(grep -i MemAvailable /proc/meminfo || echo "MemAvailable: 0 kB")
  mem_total=$((mem_total / 1024))
  mem_free=$((mem_free / 1024))
  mem_used=$((mem_total - mem_free))

  # Service health (active/inactive)
  local jellyfin plex samba
  jellyfin="$(systemctl is-active jellyfin 2>/dev/null || echo "unknown")"
  plex="$(systemctl is-active plexmediaserver 2>/dev/null || echo "unknown")"
  samba="$(systemctl is-active smbd 2>/dev/null || echo "unknown")"

  # Very small tail of system journal for context
  local logs
  if has_command journalctl; then
    logs="$(journalctl -n 50 --no-pager 2>/dev/null | sed 's/"/'\''/g')"
  else
    logs="journalctl not available"
  fi

  cat <<EOF
{
  "cpu_load": {
    "load1": $load1,
    "load5": $load5,
    "load15": $load15
  },
  "memory": {
    "total_mib": $mem_total,
    "used_mib": $mem_used,
    "free_mib": $mem_free
  },
  "services": {
    "jellyfin": "$jellyfin",
    "plexmediaserver": "$plex",
    "samba_smbd": "$samba"
  },
  "logs_tail": "$(echo "$logs" | tr '\n' ' ')"
}
EOF
}

simple_interpretation() {
  # Quick rule-based verdict if AI is not available.
  local load1="$1" mem_used="$2" mem_total="$3" jellyfin="$4" plex="$5" samba="$6"

  local issues=()

  # Heuristic thresholds
  local load_threshold
  load_threshold="$(printf "%.1f" "$(echo "$load1 > 1.5" | bc -l 2>/dev/null || echo 0)")"
  if [[ "$load_threshold" == "1.0" ]]; then
    issues+=("High CPU load (1min avg is $load1)")
  fi

  local mem_pct=$(( (mem_used * 100) / (mem_total + 1) ))
  if (( mem_pct > 90 )); then
    issues+=("High memory usage (${mem_pct}% of $mem_total MiB)")
  fi

  for svc_name in "Jellyfin:$jellyfin" "Plex:$plex" "Samba:$samba"; do
    local label="${svc_name%%:*}"
    local status="${svc_name##*:}"
    if [[ "$status" != "active" && "$status" != "unknown" ]]; then
      issues+=("Issue detected in $label service (status: $status)")
    fi
  done

  if [[ "${#issues[@]}" -eq 0 ]]; then
    echo "All systems green."
  else
    printf "Issues detected:\n"
    for i in "${issues[@]}"; do
      printf " - %s\n" "$i"
    done
  fi
}

run_ai_analysis() {
  local metrics_json="$1"

  if [[ ! -x "$AI_CLIENT" && ! -f "$AI_CLIENT" ]]; then
    echo ""
    return 0
  fi

  if ! has_command python3; then
    echo ""
    return 0
  fi

  local ai_output
  ai_output="$(printf "%s" "$metrics_json" | python3 "$AI_CLIENT" 2>/dev/null || true)"
  echo "$ai_output"
}

one_off_check_human() {
  local metrics_json
  metrics_json="$(collect_metrics_json)"

  # Extract fields with jq if available, otherwise with grep/awk
  local load1 mem_total mem_used jellyfin plex samba

  if has_command jq; then
    load1="$(printf "%s" "$metrics_json" | jq -r '.cpu_load.load1')"
    mem_total="$(printf "%s" "$metrics_json" | jq -r '.memory.total_mib')"
    mem_used="$(printf "%s" "$metrics_json" | jq -r '.memory.used_mib')"
    jellyfin="$(printf "%s" "$metrics_json" | jq -r '.services.jellyfin')"
    plex="$(printf "%s" "$metrics_json" | jq -r '.services.plexmediaserver')"
    samba="$(printf "%s" "$metrics_json" | jq -r '.services.samba_smbd')"
  else
    load1="$(echo "$metrics_json" | grep '"load1"' | head -n1 | sed 's/[^0-9\.\-]//g')"
    mem_total="$(echo "$metrics_json" | grep '"total_mib"' | head -n1 | sed 's/[^0-9]//g')"
    mem_used="$(echo "$metrics_json" | grep '"used_mib"' | head -n1 | sed 's/[^0-9]//g')"
    jellyfin="$(echo "$metrics_json" | grep '"jellyfin"' | head -n1 | sed 's/.*: *"//;s/".*//')"
    plex="$(echo "$metrics_json" | grep '"plexmediaserver"' | head -n1 | sed 's/.*: *"//;s/".*//')"
    samba="$(echo "$metrics_json" | grep '"samba_smbd"' | head -n1 | sed 's/.*: *"//;s/".*//')"
  fi

  echo "=== CustomOS Guardian Health Check ==="
  printf "CPU load (1/5/15m): %s (see AI detail if enabled)\n" "$load1"
  printf "Memory usage: %s MiB used / %s MiB total\n" "$mem_used" "$mem_total"
  printf "Services:\n"
  printf "  Jellyfin       : %s\n" "$jellyfin"
  printf "  Plex           : %s\n" "$plex"
  printf "  Samba (smbd)   : %s\n" "$samba"
  echo

  local simple verdict
  simple="$(simple_interpretation "$load1" "$mem_used" "$mem_total" "$jellyfin" "$plex" "$samba")"
  verdict="$simple"

  local ai
  ai="$(run_ai_analysis "$metrics_json")"
  if [[ -n "$ai" ]]; then
    echo "Guardian AI verdict:"
    echo "$ai"
  else
    echo "Guardian verdict:"
    echo "$verdict"
  fi
}

one_off_check_json() {
  collect_metrics_json
}

watch_loop() {
  log "INFO" "Starting Guardian watch loop (interval ${CHECK_INTERVAL_SECONDS}s)..."
  while true; do
    local metrics_json ai
    metrics_json="$(collect_metrics_json)"
    ai="$(run_ai_analysis "$metrics_json")"

    if [[ -n "$ai" ]]; then
      log "INFO" "AI analysis: $ai"
    else
      log "INFO" "Metrics: $metrics_json"
    fi

    sleep "$CHECK_INTERVAL_SECONDS"
  done
}

print_help() {
  cat <<EOF
CustomOS Guardian

Usage:
  guardian --check       Run a single human-readable health check.
  guardian --json        Output raw metrics as JSON.
  guardian --watch       Run continuously (for systemd service).
  guardian --help        Show this help.

Examples:
  guardian --check
  guardian --json | jq
EOF
}

main() {
  if [[ $# -lt 1 ]]; then
    print_help
    exit 1
  fi

  case "$1" in
    --check)
      one_off_check_human
      ;;
    --json)
      one_off_check_json
      ;;
    --watch)
      watch_loop
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
}

main "$@"

