#!/usr/bin/env bash
# Picasa — start the app and open it in your web browser.
#
#   ./run.sh                 start (runs setup automatically on first use)
#   ./run.sh --reconfigure   change the pictures / database locations
#
# If the drive was moved to another computer (different mount point), the app
# re-locates your pictures and database automatically, and only asks if it must.
set -euo pipefail
cd "$(dirname "$0")"
. ./lib.sh

{ [ "${1:-}" = "--reconfigure" ] || [ "${1:-}" = "-r" ]; } && rm -f "$CONF"

# --- configuration -----------------------------------------------------------
if [ ! -f "$CONF" ]; then
    ./setup.sh
fi
load_conf

# Heal locations if the drive moved; fall back to interactive setup if needed.
if ! resolve_paths; then
    echo "Could not find your pictures/database automatically — let's reconfigure."
    ./setup.sh
    load_conf
fi

export PHOTOS_DIR PICASADB_DIR DISPLAY_WIDTH DISPLAY_HEIGHT IMAGE
export USER_ID="$(id -u)" GROUP_ID="$(id -g)"

# --- engine + compose --------------------------------------------------------
pick_engine
pick_compose
echo "==> Using $ENGINE"

# --- macOS: ensure 32-bit Wine runs natively, not under qemu emulation ---
heal_native_i386

# --- ensure the application image is present (tar, or download to restore) ---
ensure_image || exit 1

# --- macOS: verify the app's drive is actually shared with the Docker VM ------
check_vm_sees_files

# --- launch ------------------------------------------------------------------
echo "==> Starting Picasa…"
"${COMPOSE[@]}" "${COMPOSE_FILES[@]}" up -d

printf "==> Waiting for Picasa to be ready "
for i in $(seq 1 90); do
    if curl -fsS -o /dev/null "http://localhost:5800/" 2>/dev/null; then
        echo; echo
        echo "  Picasa is ready  ->  http://localhost:5800"
        echo
        echo "     Open that address in your web browser."
        echo "     In Picasa: File > Add Folder to Picasa, then open drive  P:\\"
        echo "     (that is your pictures folder). Run ./stop.sh when finished."
        exit 0
    fi
    printf "."; sleep 2
done
echo
echo "Picasa is still starting. Check it with:  $ENGINE logs -f picasa"
echo "When ready, open:  http://localhost:5800"
