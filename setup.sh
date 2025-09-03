#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run with sudo (to install systemd/cron)" >&2
  exit 1
fi

ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT_DIR"

if [[ ! -f .env ]]; then
  echo ".env not found. Copying template..."
  cp .env.example .env
  echo "Edit .env before enabling alerts."
fi

install_systemd() {
  echo "Installing systemd service/timer..."
  install -D -m 0644 systemd/buddy-monitor.service /etc/systemd/system/buddy-monitor.service
  install -D -m 0644 systemd/buddy-monitor.timer   /etc/systemd/system/buddy-monitor.timer
  systemctl daemon-reload
  systemctl enable --now buddy-monitor.timer
  systemctl status buddy-monitor.timer --no-pager || true
  echo "systemd timer enabled (every 2 minutes). Edit /etc/systemd/system/buddy-monitor.timer to change cadence."
}

install_cron() {
  echo "Installing cron entry..."
  local me
  me=${SUDO_USER:-root}
  local cron_line="*/2 * * * * cd $ROOT_DIR && /usr/bin/env bash -lc 'source .env && ./monitor.sh' >/dev/null 2>&1"
  (crontab -u "$me" -l 2>/dev/null | grep -v 'buddy-monitor' || true; echo "$cron_line # buddy-monitor") | crontab -u "$me" -
  echo "Cron installed for user $me (every 2 minutes)."
}

printf "Install with:\n  1) systemd timer (recommended)\n  2) cron\nChoose [1/2]: "
read -r choice
case "$choice" in
  1) install_systemd ;;
  2) install_cron ;;
  *) echo "Invalid choice"; exit 1 ;;
esac

echo "Done. Test a run with: "
echo "  cd $ROOT_DIR && source .env && ./monitor.sh --once"
