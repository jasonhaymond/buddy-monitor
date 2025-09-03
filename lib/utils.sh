#!/usr/bin/env bash
set -euo pipefail

hash_target() {
  local s="$1"
  printf "%s" "$s" | md5sum | awk '{print $1}'
}

now_epoch() { date +%s; }

dlog() {
  local level="${1:-INFO}"; shift || true
  local msg="$*"
  local want="${LOG_LEVEL:-INFO}"
  if [[ "$want" == "DEBUG" || "$level" != "DEBUG" ]]; then
    echo "[$(date -Is)] [$level] $msg"
  fi
}

flush_state() {
  local file="$1"; shift
  local status="$1"; shift
  local last_epoch="$1"; shift
  cat >"$file" <<EOF
LAST_STATUS="$status"
LAST_ALERT_EPOCH=$last_epoch
EOF
}

load_state() {
  local file="$1"
  local LAST_STATUS="UNKNOWN" LAST_ALERT_EPOCH=0
  if [[ -f "$file" ]]; then
    # shellcheck disable=SC1090
    source "$file"
  fi
  echo "$LAST_STATUS $LAST_ALERT_EPOCH"
}
