#!/usr/bin/env bash
# Runs ping, HTTP, and SSL expiry checks. Sends Telegram alerts with anti-spam.
# Dependencies: bash, curl, ping (iputils / busybox), openssl, awk, date

set -euo pipefail

# Resolve to repo path so we can source libs and .env reliably from any CWD
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load env (if present)
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/.env"
fi

# Strip any stray CR characters from env (protects against CRLF .env)
for v in CHECK_TIMEOUT RETRIES COOLDOWN_SEC SSL_WARN_DAYS SSL_ALERT_DAYS \
         PING_IPS PING_HOSTS HTTP_URLS SSL_HOSTS TG_TOKEN TG_CHAT_ID STATE_DIR LOG_LEVEL; do
  if [[ -n "${!v-}" ]]; then
    eval "export $v=\"\${$v//$'\r'/}\""
  fi
done

CHECK_TIMEOUT=${CHECK_TIMEOUT:-7}
RETRIES=${RETRIES:-2}
COOLDOWN_SEC=${COOLDOWN_SEC:-900}
STATE_DIR=${STATE_DIR:-/var/tmp/buddy-monitor}
LOG_LEVEL=${LOG_LEVEL:-INFO}
SSL_WARN_DAYS=${SSL_WARN_DAYS:-21}
SSL_ALERT_DAYS=${SSL_ALERT_DAYS:-7}

mkdir -p "$STATE_DIR"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/utils.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/tg.sh"

ONE_SHOT=false
if [[ "${1:-}" == "--once" ]]; then ONE_SHOT=true; fi

should_alert_down() {
  local last_status="$1"; shift
  local last_epoch="$1"; shift
  local now; now=$(now_epoch)
  if [[ "$last_status" != "DOWN" ]]; then
    echo yes; return
  fi
  if (( now - last_epoch >= COOLDOWN_SEC )); then
    echo yes; return
  fi
  echo no
}

handle_status() {
  local key="$1"; shift
  local current_status="$1"; shift
  local ok_msg="$1"; shift
  local down_msg="$1"; shift

  local state_file="$STATE_DIR/state_$(hash_target "$key").txt"
  read -r LAST_STATUS LAST_ALERT_EPOCH < <(load_state "$state_file")
  dlog DEBUG "key=$key prev=$LAST_STATUS now=$current_status"

  if [[ "$current_status" == "DOWN" ]]; then
    if [[ $(should_alert_down "$LAST_STATUS" "$LAST_ALERT_EPOCH") == yes ]]; then
      tg_alert "$down_msg"
      LAST_ALERT_EPOCH=$(now_epoch)
    fi
  else
    if [[ "$LAST_STATUS" == "DOWN" ]]; then
      tg_alert "$ok_msg"
      LAST_ALERT_EPOCH=$(now_epoch)
    else
      dlog DEBUG "still UP; no alert"
    fi
  fi
  flush_state "$state_file" "$current_status" "$LAST_ALERT_EPOCH"
}

# -------- PING (IPs) --------
IFS="," read -r -a PING_IPS_ARR <<< "${PING_IPS:-}"
for ip in "${PING_IPS_ARR[@]}"; do
  [[ -z "$ip" ]] && continue
  ip=$(echo "$ip" | xargs)
  [[ -z "$ip" ]] && continue

  fails=0
  for i in $(seq 1 "$RETRIES"); do
    if ping -c1 -W "$CHECK_TIMEOUT" "$ip" >/dev/null 2>&1; then
      break
    fi
    fails=$((fails+1)); sleep 1
  done
  status=UP
  [[ $fails -ge $RETRIES ]] && status=DOWN

  handle_status "ping:ip:$ip" "$status" \
    "✅ PING OK: \`$ip\`" \
    "❌ PING DOWN: \`$ip\`"

done

# -------- PING (hosts) --------
IFS="," read -r -a PING_HOSTS_ARR <<< "${PING_HOSTS:-}"
for host in "${PING_HOSTS_ARR[@]}"; do
  [[ -z "$host" ]] && continue
  host=$(echo "$host" | xargs)
  [[ -z "$host" ]] && continue

  fails=0
  for i in $(seq 1 "$RETRIES"); do
    if ping -c1 -W "$CHECK_TIMEOUT" "$host" >/dev/null 2>&1; then
      break
    fi
    fails=$((fails+1)); sleep 1
  done
  status=UP
  [[ $fails -ge $RETRIES ]] && status=DOWN

  handle_status "ping:host:$host" "$status" \
    "✅ PING OK: \`$host\`" \
    "❌ PING DOWN: \`$host\`"

done

# -------- HTTP --------
IFS="," read -r -a HTTP_URLS_ARR <<< "${HTTP_URLS:-}"
for url in "${HTTP_URLS_ARR[@]}"; do
  [[ -z "$url" ]] && continue
  url=$(echo "$url" | xargs)
  [[ -z "$url" ]] && continue

  fails=0
  code=000
  for i in $(seq 1 "$RETRIES"); do
    code=$(curl -fsS -o /dev/null -m "$CHECK_TIMEOUT" -w '%{http_code}' "$url" || echo 000)
    HTTP_OK_REGEX="${HTTP_OK_REGEX:-^[23]}"
    if [[ "$code" =~ $HTTP_OK_REGEX ]]; then
      break
    fi
    fails=$((fails+1)); sleep 1
  done
  status=UP
  if [[ ! "$code" =~ ^[23] ]] && [[ $fails -ge $RETRIES ]]; then
    status=DOWN
  fi

  handle_status "http:$url" "$status" \
    "✅ HTTP OK: \`$url\` (code $code)" \
    "❌ HTTP DOWN: \`$url\` (code $code)"

done

# -------- SSL EXPIRY --------
IFS="," read -r -a SSL_HOSTS_ARR <<< "${SSL_HOSTS:-}"
for hp in "${SSL_HOSTS_ARR[@]}"; do
  [[ -z "$hp" ]] && continue
  hp=$(echo "$hp" | xargs)
  [[ -z "$hp" ]] && continue

  host=${hp%%:*}
  port=${hp##*:}
  [[ "$port" == "$host" ]] && port=443

  # Fetch notAfter, compute days left
  not_after=$(echo | timeout "$CHECK_TIMEOUT" openssl s_client -servername "$host" -connect "$host:$port" 2>/dev/null \
    | openssl x509 -noout -enddate 2>/dev/null \
    | sed -E 's/^notAfter=//') || not_after=""

  if [[ -z "$not_after" ]]; then
    handle_status "ssl:$host:$port" DOWN \
      "✅ SSL OK (could read cert): \`$host:$port\`" \
      "❌ SSL CHECK FAILED: \`$host:$port\` (no cert info)"
    continue
  fi

  exp_epoch=$(date -d "$not_after" +%s 2>/dev/null || true)
  now=$(now_epoch)
  if [[ -z "$exp_epoch" ]]; then
    handle_status "ssl:$host:$port" DOWN \
      "✅ SSL OK (parsed): \`$host:$port\`" \
      "❌ SSL PARSE FAILED: \`$host:$port\` ($not_after)"
    continue
  fi
  days_left=$(( (exp_epoch - now) / 86400 ))

  if (( days_left <= SSL_ALERT_DAYS )); then
    handle_status "ssl:$host:$port" DOWN \
      "✅ SSL RECOVERED: \`$host:$port\` now valid > ${SSL_ALERT_DAYS}d" \
      "❌ SSL EXPIRING: \`$host:$port\` in ${days_left}d (<= ${SSL_ALERT_DAYS}d)"
  elif (( days_left <= SSL_WARN_DAYS )); then
    handle_status "ssl:$host:$port" DOWN \
      "✅ SSL RECOVERED: \`$host:$port\` now valid > ${SSL_WARN_DAYS}d" \
      "⚠️  SSL WARNING: \`$host:$port\` in ${days_left}d (<= ${SSL_WARN_DAYS}d)"
  else
    handle_status "ssl:$host:$port" UP \
      "✅ SSL OK: \`$host:$port\` (${days_left}d left)" \
      "❌ SSL UNKNOWN: \`$host:$port\`"
  fi

done

$ONE_SHOT && exit 0 || true
