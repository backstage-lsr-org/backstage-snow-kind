#!/bin/sh
# entrypoint.sh — zero-dependency supervisor for the SNow mock + Backstage.
# Auto-detects the Backstage entry point (index.js vs index.cjs.js).

set -e

log() { echo "[$(date -Iseconds)] [supervisor] $*"; }

# ── Detect entry point ───────────────────────────────────────────────────────
DIST=/app/packages/backend/dist
if [ -f "$DIST/index.cjs.js" ]; then
  ENTRY="$DIST/index.cjs.js"
elif [ -f "$DIST/index.js" ]; then
  ENTRY="$DIST/index.js"
else
  log "ERROR: no entry point found in $DIST"
  ls -la "$DIST" || true
  exit 1
fi
log "Backstage entry point: $ENTRY"

# ── Process start functions ──────────────────────────────────────────────────
start_mock() {
  log "Starting ServiceNow mock on :8181"
  MOCK_PORT=8181 node /mock/server.js &
  MOCK_PID=$!
  log "Mock PID=$MOCK_PID"
}

start_backstage() {
  log "Starting Backstage on :7007"
  cd /app
  NODE_ENV=production node "$ENTRY" --config app-config.yaml &
  BS_PID=$!
  log "Backstage PID=$BS_PID"
}

# ── Graceful shutdown ────────────────────────────────────────────────────────
shutdown() {
  log "Shutdown signal received"
  kill "$MOCK_PID" "$BS_PID" 2>/dev/null || true
  wait
  log "Stopped."
  exit 0
}
trap shutdown TERM INT

# ── Start both ───────────────────────────────────────────────────────────────
start_mock
sleep 2
start_backstage

log "Both services running. Supervisor watching..."
while true; do
  sleep 10
  if ! kill -0 "$MOCK_PID" 2>/dev/null; then
    log "WARN: Mock crashed — restarting"
    start_mock
  fi
  if ! kill -0 "$BS_PID" 2>/dev/null; then
    log "WARN: Backstage crashed — restarting"
    start_backstage
  fi
done
