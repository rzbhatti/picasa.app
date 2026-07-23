#!/usr/bin/env bash
# Picasa — configuration. Asks where your pictures are and where to keep the
# Picasa database, and saves your answers to picasa.conf.
#
#   ./setup.sh
#
# Safe to run again any time to change the locations.
set -euo pipefail
cd "$(dirname "$0")"
. ./lib.sh

# Pre-load current values (shown as defaults) if already configured.
[ -f "$CONF" ] && load_conf
APP_DRIVE="$(drive_root "$APP_DIR")"

echo "======================================================"
echo "  Picasa — setup"
echo "======================================================"
echo

# --- 1. Pictures -------------------------------------------------------------
echo "1) Where are the PICTURES you want Picasa to manage?"
echo "   Enter the full path to that folder (it must already exist)."
if [ -n "${PHOTOS_DIR:-}" ]; then printf "   Pictures folder [%s]: " "$PHOTOS_DIR"; else printf "   Pictures folder: "; fi
read -r _in
if [ -n "$_in" ]; then PHOTOS_DIR="$(expand_path "$_in")"; fi
if [ -z "${PHOTOS_DIR:-}" ] || [ ! -d "$PHOTOS_DIR" ]; then
    echo "   ERROR: '${PHOTOS_DIR:-}' is not an existing folder." >&2
    exit 1
fi
echo

# --- 2. Database -------------------------------------------------------------
echo "2) Where should Picasa STORE ITS DATABASE?"
echo "   (photo index, thumbnails, albums and face names — any drive/folder is"
echo "    fine; keeping it on the same drive as your pictures makes the whole"
echo "    thing portable.)"

# Offer a smart default: an existing DB on this drive, else the app's own folder.
_found="$(locate_picasadb "$APP_DRIVE" | head -n1 || true)"
if [ -n "${PICASADB_DIR:-}" ]; then _default="$PICASADB_DIR"
elif [ -n "$_found" ];          then _default="$_found"
else                                 _default="$APP_DIR/PicasaDB"; fi

printf "   Database folder [%s]: " "$_default"
read -r _in
if [ -n "$_in" ]; then PICASADB_DIR="$(expand_path "$_in")"; else PICASADB_DIR="$_default"; fi
if ! mkdir -p "$PICASADB_DIR" 2>/dev/null; then
    echo "   ERROR: cannot create '$PICASADB_DIR'." >&2
    exit 1
fi
echo

# --- save --------------------------------------------------------------------
PHOTOS_ONDRIVE="$(subpath_on_drive "$PHOTOS_DIR" "$APP_DRIVE")"
PICASADB_ONDRIVE="$(subpath_on_drive "$PICASADB_DIR" "$APP_DRIVE")"
: "${DISPLAY_WIDTH:=1920}"; : "${DISPLAY_HEIGHT:=1080}"
write_conf

echo "Saved to picasa.conf:"
echo "   Pictures : $PHOTOS_DIR"
echo "   Database : $PICASADB_DIR"
echo
echo "Now start Picasa with:   ./run.sh"
