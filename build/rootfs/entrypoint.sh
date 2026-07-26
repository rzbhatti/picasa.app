#!/bin/bash
# PID 1. Runs as root: fixes up the runtime user, seeds the persistent Wine
# prefix on first run, wires photo storage into Wine, then drops privileges
# and hands off to supervisord.
set -euo pipefail

USER_ID="${USER_ID:-1000}"
GROUP_ID="${GROUP_ID:-1000}"
APP_USER=app
CONFIG_PREFIX=/config/wine
DEFAULT_PREFIX=/opt/wine-defaults
PHOTOS_DIR=/storage/photos

echo "==> Starting ${APP_NAME:-Picasa} container"

# --- runtime user matches the host UID/GID so bind mounts stay writable ------
if ! getent group "$GROUP_ID" >/dev/null 2>&1; then
    groupadd -g "$GROUP_ID" "$APP_USER"
fi
if ! getent passwd "$USER_ID" >/dev/null 2>&1; then
    useradd -u "$USER_ID" -g "$GROUP_ID" -d /config -s /bin/bash "$APP_USER"
fi
APP_USER="$(getent passwd "$USER_ID" | cut -d: -f1)"

# --- defensive: clear any stale/root-owned Wine server dirs in /tmp ----------
# (a root-owned /tmp/wine-* baked into the image would block the app user's Wine)
rm -rf /tmp/.wine-* /tmp/wine-* 2>/dev/null || true

# --- persistent directories --------------------------------------------------
mkdir -p /config /storage "$PHOTOS_DIR"

# --- first-run: seed the persisted Wine prefix from the baked one ------------
if [ ! -d "$CONFIG_PREFIX" ]; then
    echo "==> First run: seeding Wine prefix into /config/wine (this persists)"
    cp -a "$DEFAULT_PREFIX" "$CONFIG_PREFIX"
else
    echo "==> Reusing existing Wine prefix at /config/wine"
fi

# --- expose photos inside Wine as drive P: (Z: already maps to / ) -----------
mkdir -p "$CONFIG_PREFIX/dosdevices"
ln -sfn "$PHOTOS_DIR" "$CONFIG_PREFIX/dosdevices/p:"

# --- ownership so the unprivileged app user can read/write everything --------
# Recurse only /config (the Wine prefix volume). Do NOT recurse /storage: it may
# be a huge external/SSD mount (and exFAT/NTFS ignore ownership anyway), so we
# only fix the top-level mount points there.
chown -R "$USER_ID:$GROUP_ID" /config 2>/dev/null || true
chown "$USER_ID:$GROUP_ID" /storage "$PHOTOS_DIR" 2>/dev/null || true

# --- timezone ----------------------------------------------------------------
if [ -n "${TZ:-}" ] && [ -f "/usr/share/zoneinfo/$TZ" ]; then
    ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
    echo "$TZ" > /etc/timezone
fi

# supervisord runs as root so it can write child logs to the container's stdout
# (/dev/stdout); each managed program drops to the app user via `user=` in the
# supervisor config (APP_USERNAME below).
export APP_USERNAME="$APP_USER"
echo "==> Launching services (Xvfb, openbox, x11vnc, noVNC, Picasa) as $APP_USER (uid $USER_ID)"
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
