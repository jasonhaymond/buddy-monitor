#!/usr/bin/env bash
set -euo pipefail

TG_TOKEN=${TG_TOKEN:-}
TG_CHAT_ID=${TG_CHAT_ID:-}

if [[ -z "${TG_TOKEN}" || -z "${TG_CHAT_ID}" ]]; then
  echo "[tg] Missing TG_TOKEN or TG_CHAT_ID" >&2
  exit 1
fi

_tg_send() {
  local text="$1"
  curl -fsS -G "https://api.telegram.org/bot${TG_TOKEN}/sendMessage"         --data-urlencode "chat_id=${TG_CHAT_ID}"         --data-urlencode "text=${text}"         --data-urlencode "parse_mode=Markdown" >/dev/null
}

TG_PREFIX=${TG_PREFIX:-"buddy-monitor"}

tg_info()  { _tg_send "_${TG_PREFIX}:_ ${1}"; }

tg_alert() { _tg_send "*${TG_PREFIX}:* ${1}"; }
