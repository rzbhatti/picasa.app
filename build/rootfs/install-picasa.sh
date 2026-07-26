#!/bin/bash
# Build-time silent install of Picasa 3.9 into a baked Wine prefix.
# Runs headless under Xvfb (there is no display during `docker build`).
set -euo pipefail

export WINEARCH=win32
export WINEPREFIX=/opt/wine-defaults
export WINEDEBUG=-all
# mscoree/mshtml=disabled stops Wine from trying to pull Mono/Gecko installers.
export WINEDLLOVERRIDES="mscoree=d;mshtml=d"

echo "==> Initializing 32-bit Wine prefix at ${WINEPREFIX}"
# NOTE: on Docker Desktop for Mac the 32-bit Wine binaries run through
# qemu-i386 (binfmt) emulation, so every wine step here is SLOW. Timeouts are
# sized generously to accommodate that; on a native Linux/amd64 host these
# steps finish in seconds.
#
# xvfb-run gives wine a display for the whole build-time session. We deliberately
# AVOID `wineserver -w` (it blocks until the server exits, and wineboot can leave
# a persistent explorer/desktop process alive -> indefinite hang). Instead we use
# bounded waits and force-terminate the server with `wineserver -k` at the end.
xvfb-run -a --server-args="-screen 0 1024x768x24" bash -euo pipefail -c '
    echo "==> wineboot --init (initializing prefix)"
    # timeout guards against emulation stalls; wineboot exit status is advisory.
    timeout 600 wineboot --init || true

    # Bounded wait for the prefix skeleton to appear.
    for i in $(seq 1 120); do
        [ -d "${WINEPREFIX}/drive_c/windows" ] && break
        sleep 2
    done
    if [ ! -d "${WINEPREFIX}/drive_c/windows" ]; then
        echo "ERROR: Wine prefix failed to initialize." >&2
        exit 1
    fi
    sleep 5   # let first-run bookkeeping settle (no blocking wait on server exit)

    # Font coverage comes from fonts-liberation (installed via apt, from Debian
    # main): metric-compatible Arial/Times/Courier that Wine substitutes for the
    # MS core fonts Picasa expects. No build-time font download needed.

    echo "==> Running Picasa silent install (/S)"
    # timeout so a stuck installer cannot hang the whole build indefinitely.
    timeout 900 wine /tmp/picasa39-setup.exe /S || true

    # NSIS /S forks; poll until the main binary lands (or time out).
    PICASA_EXE=""
    for i in $(seq 1 150); do
        found=$(find "${WINEPREFIX}/drive_c" -iname "Picasa3.exe" 2>/dev/null | head -n1 || true)
        if [ -n "$found" ]; then PICASA_EXE="$found"; break; fi
        sleep 2
    done

    if [ -z "$PICASA_EXE" ]; then
        echo "ERROR: Picasa3.exe not found after silent install." >&2
        echo "The /S flag may not have completed non-interactively." >&2
        find "${WINEPREFIX}/drive_c" -iname "*picasa*" 2>/dev/null >&2 || true
        wineserver -k 2>/dev/null || true
        exit 1
    fi

    echo "==> Picasa installed at: $PICASA_EXE"
    # Record the discovered path so the launcher does not have to re-search.
    echo "$PICASA_EXE" > "${WINEPREFIX}/picasa-exe-path.txt"

    # Cleanly shut the prefix down so the build layer is quiescent.
    wineserver -k 2>/dev/null || true
    sleep 3
'

echo "==> Trimming Wine caches to reduce image size"
rm -rf /root/.cache/wine /root/.cache/winetricks 2>/dev/null || true
# CRITICAL: remove the root-owned Wine server dirs this build created under /tmp.
# If baked into the image they shadow the app user's Wine at runtime and cause
# "wine: chdir to /tmp/wine-...: Permission denied" crash loops.
rm -rf /tmp/.wine-* /tmp/wine-* /tmp/.X*-lock /tmp/.X11-unix 2>/dev/null || true

echo "==> Baked prefix ready at ${WINEPREFIX}"
