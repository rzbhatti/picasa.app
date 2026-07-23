#!/usr/bin/env bash
# Picasa — stop the app. Your pictures and database are left untouched.
set -euo pipefail
cd "$(dirname "$0")"
. ./lib.sh

# Load config if present so compose can parse; otherwise use harmless defaults.
[ -f "$CONF" ] && load_conf
export PHOTOS_DIR="${PHOTOS_DIR:-/tmp}" PICASADB_DIR="${PICASADB_DIR:-/tmp}"
export DISPLAY_WIDTH="${DISPLAY_WIDTH:-1920}" DISPLAY_HEIGHT="${DISPLAY_HEIGHT:-1080}"
export USER_ID="$(id -u)" GROUP_ID="$(id -g)" IMAGE

pick_engine
pick_compose

echo "==> Stopping Picasa…"
if ! "${COMPOSE[@]}" "${COMPOSE_FILES[@]}" down 2>/dev/null; then
    # Fallback if compose parsing fails for any reason.
    $ENGINE rm -f picasa >/dev/null 2>&1 || true
fi
echo "==> Stopped. Your pictures and database are safe."
