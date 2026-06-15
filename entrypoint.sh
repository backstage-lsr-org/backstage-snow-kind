#!/bin/sh
# entrypoint.sh — starts both the ServiceNow mock and Backstage, restarts either if they crash

set -e

log() { echo "[$(date -Iseconds)] [supervisor] $*"; }

# ── Start ServiceNow mock ─────────────────────────────────────────────────────
start_mock() {
  log "Starting ServiceNow mock on :8181"
  MOCK_PORT=8181 node /mock/server.js &
  MOCK_PID=$!
  log "Mock PID=$MOCK_PID"
}

# ── Start Backstage ────────────────────────────────────────────────────────────
start_backstage() {
  log "Starting Backstage on :7007"
  cd /app
  NODE_ENV=production node dist/index.cjs.js --config app-config.yaml &
  BS_PID=$!
  log "Backstage PID=$BS_PID"
}

# ── Graceful shutdown on SIGTERM/SIGINT ───────────────────────────────────────
shutdown() {
  log "Shutting down..."
  kill "$MOCK_PID" "$BS_PID" 2>/dev/null || true
  wait
  log "All processes stopped."
  exit 0
}
trap shutdown TERM INT

# ── Initial start ─────────────────────────────────────────────────────────────
start_mock
# Small delay so mock is ready before Backstage tries to call it on startup
sleep 2
start_backstage

# ── Watch loop: restart crashed processes ─────────────────────────────────────
log "Supervisor running. Both services started."
while true; do
  sleep 5

  if ! kill -0 "$MOCK_PID" 2>/dev/null; then
    log "WARN: Mock crashed (PID=$MOCK_PID) — restarting"
    start_mock
  fi

  if ! kill -0 "$BS_PID" 2>/dev/null; then
    log "WARN: Backstage crashed (PID=$BS_PID) — restarting"
    start_backstage
  fi
done
