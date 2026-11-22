#!/usr/bin/env bash
# Stops the six services and the containers. Pass --wipe to delete the database volume too.
set -uo pipefail
source "$(dirname "$0")/env.sh"
require_env
cd "$SERVICES_DIR"

for entry in $SERVICES; do
  name="${entry%%:*}"; port="${entry##*:}"
  pids="$(cat "$LOG_DIR/$name.pid" 2>/dev/null) $(lsof -ti "tcp:$port" -sTCP:LISTEN 2>/dev/null)"
  for pid in $pids; do kill "$pid" 2>/dev/null && echo "Stopped $name ($pid)"; done
  rm -f "$LOG_DIR/$name.pid"
done

if [ "${1:-}" = "--wipe" ]; then docker compose down -v; else docker compose down; fi
