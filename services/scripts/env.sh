# Shared settings for the scripts. Sourced, not run.
SERVICES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$SERVICES_DIR/logs"
SERVICES="auth:8081 account:8082 lookup:8083 payment:8084 mock-directory:8085 mock-fast:8086"

# Pick a Java 17 JDK: JAVA_HOME if it works, otherwise the java on PATH.
if [ -z "${JAVA_HOME:-}" ] || [ ! -x "$JAVA_HOME/bin/java" ]; then
  JAVA_BIN="$(command -v java)"
  JAVA_HOME="$(cd "$(dirname "$(readlink -f "$JAVA_BIN")")/.." && pwd)"
fi
export JAVA_HOME

# Load services/.env when it exists, then check the variables the stack needs.
if [ -f "$SERVICES_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$SERVICES_DIR/.env"
  set +a
fi

require_env() {
  local missing=""
  for var in JWT_SECRET DB_PASSWORD DB_ROOT_PASSWORD; do
    if [ -z "${!var:-}" ]; then missing="$missing $var"; fi
  done
  if [ -n "$missing" ]; then
    echo "Missing:$missing. Copy services/.env.example to services/.env and fill in each value." >&2
    exit 1
  fi
}
