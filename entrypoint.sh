#!/bin/sh
# Supervisor: starts ServiceNow mock + Backstage, restarts either on crash.

set -e
log() { echo "[$(date -Iseconds)] [supervisor] $*"; }

start_mock() {
  log "Starting ServiceNow mock on :8181"
  MOCK_PORT=8181 node /mock/server.js &
  MOCK_PID=$!
  log "Mock PID=$MOCK_PID"
}

start_backstage() {
  log "Starting Backstage on :7007"
  cd /app
  # Official entry point per Backstage docs
  node packages/backend --config app-config.yaml &
  BS_PID=$!
  log "Backstage PID=$BS_PID"
}

shutdown() {
  log "Shutdown signal received — stopping all processes"
  kill "$MOCK_PID" "$BS_PID" 2>/dev/null || true
  wait
  exit 0
}
trap shutdown TERM INT

start_mock
sleep 2
start_backstage

log "Both services running. Watching for crashes..."
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
