#!/usr/bin/env bash
# Starts MariaDB and Kafka, builds the services that aren't running yet, and runs them in the background.
# FAST_PROFILE=today scripts/up.sh gives mock-fast the 2 s FAST delay.
# LATENCY_PROFILE=measured scripts/up.sh gives every service the delays in ../latency/measured.json.
# A service that is already up keeps its jar and its profile. Run scripts/down.sh first to change either.
set -euo pipefail
source "$(dirname "$0")/env.sh"
require_env
cd "$SERVICES_DIR"
mkdir -p "$LOG_DIR"

echo "Starting MariaDB and Kafka"
docker compose up -d --wait

start=""
for entry in $SERVICES; do
  name="${entry%%:*}"; port="${entry##*:}"
  if curl -sf "http://localhost:$port/health" >/dev/null 2>&1; then
    echo "$name already up on $port"
  else
    start="$start $name"
  fi
done

if [ -n "$start" ]; then
  echo "Building$start"
  ./gradlew -q $(for name in $start; do printf ':%s:bootJar ' "$name"; done)
fi

for name in $start; do
  profiles="${LATENCY_PROFILE:-}"
  if [ "$name" = "mock-fast" ] && [ -n "${FAST_PROFILE:-}" ]; then profiles="${profiles:+$profiles,}$FAST_PROFILE"; fi
  args=()
  if [ -n "$profiles" ]; then args+=("--spring.profiles.active=$profiles"); fi
  nohup "$JAVA_HOME/bin/java" -Xmx256m -XX:TieredStopAtLevel=1 -Duser.timezone=UTC \
    -jar "$name/build/libs/$name.jar" ${args[@]+"${args[@]}"} > "$LOG_DIR/$name.log" 2>&1 &
  echo $! > "$LOG_DIR/$name.pid"
  echo "Started $name (pid $!)${profiles:+ with profile $profiles}, log in logs/$name.log"
done

echo "Waiting for health checks"
for entry in $SERVICES; do
  name="${entry%%:*}"; port="${entry##*:}"
  for i in $(seq 1 90); do
    if curl -sf "http://localhost:$port/health" >/dev/null 2>&1; then echo "  $name UP"; break; fi
    if [ "$i" = 90 ]; then echo "  $name did not come up, see logs/$name.log"; exit 1; fi
    sleep 1
  done
done
echo "All services up"
