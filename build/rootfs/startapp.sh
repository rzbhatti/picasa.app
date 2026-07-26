#!/bin/bash
# Launches Picasa under Wine on the virtual display. Run by supervisord as the
# app user, after Xvfb/openbox/x11vnc are up.
set -uo pipefail

export DISPLAY=:0
export WINEARCH=win32
export WINEPREFIX=/config/wine
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree=d;mshtml=d}"
export HOME=/config

# Give the X server / WM a moment to settle before the first wine call.
for i in $(seq 1 30); do
    xdotool getdisplaygeometry >/dev/null 2>&1 && break
    sleep 1
done

# Locate Picasa3.exe. Prefer the path recorded at build time; otherwise search.
PICASA_EXE=""
if [ -f "$WINEPREFIX/picasa-exe-path.txt" ]; then
    PICASA_EXE="$(cat "$WINEPREFIX/picasa-exe-path.txt")"
fi
if [ -z "$PICASA_EXE" ] || [ ! -f "$PICASA_EXE" ]; then
    PICASA_EXE="$(find "$WINEPREFIX/drive_c" -iname 'Picasa3.exe' 2>/dev/null | head -n1)"
fi

if [ -z "$PICASA_EXE" ] || [ ! -f "$PICASA_EXE" ]; then
    echo "ERROR: Picasa3.exe not found under $WINEPREFIX/drive_c." >&2
    echo "See the README 'Picasa does not appear' troubleshooting section." >&2
    # Keep the container's desktop alive so the user can debug via noVNC.
    exec openbox --replace 2>/dev/null || sleep infinity
fi

# Optional: relocate Picasa's database/catalog (index, thumbnails, albums,
# contacts.xml/face-names) to a custom directory via the AppLocalDataPath
# registry key. Set PICASA_DATA_DIR to a container path (e.g. a folder
# bind-mounted from an external/SSD volume) to persist the catalog there as
# plain files -- this works even on filesystems that can't host a Wine prefix
# (exFAT/NTFS), because only regular files are written to it.
if [ -n "${PICASA_DATA_DIR:-}" ]; then
    mkdir -p "$PICASA_DATA_DIR"
    WIN_DATA_PATH="$(winepath -w "$PICASA_DATA_DIR" 2>/dev/null)"
    if [ -n "$WIN_DATA_PATH" ]; then
        # Picasa expects a trailing backslash on this path.
        case "$WIN_DATA_PATH" in *\\) ;; *) WIN_DATA_PATH="${WIN_DATA_PATH}\\" ;; esac
        echo "==> Setting Picasa data dir (AppLocalDataPath) = $WIN_DATA_PATH"
        wine reg add "HKCU\\Software\\Google\\Picasa\\Picasa2\\Preferences" \
            /v AppLocalDataPath /t REG_SZ /d "$WIN_DATA_PATH" /f >/dev/null 2>&1 \
            || echo "WARN: failed to set AppLocalDataPath"
    else
        echo "WARN: could not resolve Windows path for $PICASA_DATA_DIR"
    fi
fi

echo "==> Launching Picasa: $PICASA_EXE"
# Maximize the window shortly after it appears so it fills the noVNC viewport.
(
    for i in $(seq 1 60); do
        wid=$(xdotool search --name "Picasa" 2>/dev/null | head -n1 || true)
        if [ -n "$wid" ]; then
            xdotool windowactivate "$wid" 2>/dev/null || true
            wmctrl -ir "$wid" -b add,maximized_vert,maximized_horz 2>/dev/null || \
                xdotool windowsize "$wid" 100% 100% 2>/dev/null || true
            break
        fi
        sleep 1
    done
) &

cd /config
exec wine "$PICASA_EXE"
