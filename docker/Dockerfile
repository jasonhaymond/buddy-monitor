# Minimal image with bash, curl, openssl, iputils-ping, coreutils, ca-certs, tzdata, cron
FROM alpine:3.20

RUN apk add --no-cache bash curl openssl iputils coreutils ca-certificates tzdata busybox-extras crond

WORKDIR /app
# copy only what's needed for runtime
COPY ../monitor.sh ./monitor.sh
COPY ../lib ./lib
COPY ../.env.example .env

RUN chmod +x monitor.sh lib/*.sh

# Persist state under standard path
ENV STATE_DIR=/var/tmp/buddy-monitor
VOLUME ["/var/tmp/buddy-monitor"]

# Healthcheck does a one-shot run
HEALTHCHECK --interval=2m --timeout=20s --start-period=20s --retries=2       CMD bash -lc "./monitor.sh --once >/dev/null 2>&1 || exit 1"

# Default cron schedule (override at runtime with CRON_EXPR)
ENV CRON_EXPR="*/2 * * * *"
RUN echo "$CRON_EXPR /bin/bash -lc 'source /app/.env && /app/monitor.sh'" >> /etc/crontabs/root

CMD ["/bin/sh", "-lc", "printenv CRON_EXPR >/tmp/cron && sed -i "1s|.*|$CRON_EXPR /bin/bash -lc 'source /app/.env && /app/monitor.sh'|" /etc/crontabs/root && crond -f -l 8"]
