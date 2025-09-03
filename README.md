# buddy-monitor (Telegram)

External uptime monitoring you can host on a friend's (or your own external) Linux box. Sends Telegram alerts when your **home lab** or personal services are unreachable.

## What it checks
- **Ping**: IPs (raw) and hostnames (DNS + ping)
- **HTTP(S)**: GET request with timeout; non-2xx/3xx is considered DOWN
- **SSL expiry**: Warns/alerts when a cert is near expiry (threshold configurable)

## Features
- Multiple targets for each check type
- Telegram alerts for **DOWN** and **RECOVERY** (with spam throttling)
- Minimal state (per-target files in `/var/tmp/buddy-monitor`)
- Configure via `.env`
- Install as **systemd timer** or **cron**
- **Docker / Compose** deployment option

---

## Quick start

### Option A — Native (systemd/cron)
1. **Clone** this repo on your buddy's machine (Debian/Ubuntu/Alpine/CentOS etc.).
2. Copy env template and edit:
   ```bash
   cp .env.example .env
   $EDITOR .env
   ```
3. **Test run**:
   ```bash
   ./monitor.sh --once
   ```
4. **Install** (choose systemd or cron):
   ```bash
   sudo ./setup.sh
   ```

### Option B — Docker / Compose
1. Copy env template and edit:
   ```bash
   cp .env.example .env
   $EDITOR .env
   ```
2. Start with Compose:
   ```bash
   cd docker
   docker compose up -d
   ```
   - Container runs every 2 minutes (via cron inside container) and reads your `.env` from repo root (`../.env` in compose).
   - State is persisted in a Docker volume.
3. Logs:
   ```bash
   docker compose logs -f
   ```
4. Manual one-shot run:
   ```bash
   docker compose run --rm buddy-monitor ./monitor.sh --once
   ```

---

## Configuration (.env)

| Variable | Description |
|---|---|
| `TG_TOKEN` | Telegram Bot token from @BotFather |
| `TG_CHAT_ID` | Chat ID (user or group). For groups, it's a negative number |
| `PING_IPS` | Comma-separated IP list to ping (e.g. `1.2.3.4,9.9.9.9`) |
| `PING_HOSTS` | Comma-separated hostnames to ping (e.g. `example.com,chat.haymondtechnologies.com`) |
| `HTTP_URLS` | Comma-separated URLs to check via HTTP(S) |
| `SSL_HOSTS` | Comma-separated hostnames (optionally `host:port`) for TLS expiry checks |
| `HTTP_OK_REGEX` | Define HTTP valid responses in REGEX |
| `SSL_WARN_DAYS` | Days before expiry to trigger **warning** (default 21) |
| `SSL_ALERT_DAYS` | Days before expiry to trigger **alert** (default 7) |
| `CHECK_TIMEOUT` | Per-check timeout seconds (default 7) |
| `RETRIES` | Consecutive failures to mark DOWN (default 2) |
| `COOLDOWN_SEC` | Minimum seconds between repeat DOWN alerts (default 900) |
| `STATE_DIR` | State path (default `/var/tmp/buddy-monitor`) |
| `LOG_LEVEL` | `INFO` or `DEBUG` |

**Note:** Leave any list empty to skip that check type.

---

## Operations

- **Manual run (native)**: `./monitor.sh --once`
- **Manual run (Docker)**: `cd docker && docker compose run --rm buddy-monitor ./monitor.sh --once`
- **Verbose**: `LOG_LEVEL=DEBUG ./monitor.sh --once` or `docker compose run -e LOG_LEVEL=DEBUG --rm buddy-monitor ./monitor.sh --once`
- **Change interval (native)**: edit `systemd/buddy-monitor.timer` or cron schedule.
- **Change interval (Docker)**: edit `docker/docker-compose.yml` `CRON_EXPR` env var.

---

## Security
- Uses only Telegram HTTPS API; no inbound ports required.
- Stores minimal state (status + last alert epoch) per target.
- Keep your `.env` readable only by the service user: `chmod 600 .env`.

---

## License
MIT — see [LICENSE](LICENSE).

---

## CI
GitHub Actions runs ShellCheck and bash `-n` to lint scripts on push/PR and also builds the Docker image.
