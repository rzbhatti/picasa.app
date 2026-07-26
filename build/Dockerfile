# Picasa 3.9 (32-bit Windows app) under Wine, streamed to a browser via noVNC.
# Built entirely from official Debian packages -- no third-party repos, no git clones.
FROM debian:bookworm-slim

# ---------------------------------------------------------------------------
# 1. System packages: Wine (32-bit), a virtual X stack, and the noVNC bridge.
# ---------------------------------------------------------------------------
# wine + wine32:i386  -> run the 32-bit Picasa binary
# xvfb                -> headless X server (a virtual framebuffer)
# openbox             -> minimal window manager so Picasa's window is managed
# x11vnc              -> expose the X display over VNC (localhost only)
# novnc + websockify  -> serve the VNC session to a browser on :5800
# winbind             -> ntlm_auth, silences a common Wine warning
# fonts-liberation    -> metric-compatible Arial/Times/Courier (fixes Picasa
#                        blank/garbled text) -- from Debian main, no download
# gosu                -> drop privileges cleanly from the entrypoint
# xdotool             -> used by the launcher to nudge/maximize the window
ENV DEBIAN_FRONTEND=noninteractive
RUN dpkg --add-architecture i386 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        wine \
        wine32:i386 \
        xvfb \
        xauth \
        x11vnc \
        openbox \
        supervisor \
        novnc \
        websockify \
        winbind \
        fonts-liberation \
        gosu \
        xdotool \
        wmctrl \
        procps \
        ca-certificates \
        tzdata \
    && rm -rf /var/lib/apt/lists/*

# noVNC ships the client as vnc.html; make it the default page so the browser
# lands straight on the session at http://host:5800/
RUN ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html

# ---------------------------------------------------------------------------
# 2. Rootfs: entrypoint, supervisor config, launcher, and the build installer.
# ---------------------------------------------------------------------------
COPY rootfs/ /
RUN chmod +x /entrypoint.sh /startapp.sh /install-picasa.sh

# ---------------------------------------------------------------------------
# 3. Silent install of Picasa into a BAKED prefix at /opt/wine-defaults.
#    The prefix is baked outside /config so the runtime ./config bind-mount
#    doesn't shadow it; entrypoint.sh seeds /config/wine from it on first run.
#    Installer is copied and removed in this single layer to keep size down.
#
#    picasa39-setup.exe is NOT in this repository -- Picasa is discontinued
#    Google proprietary software. Keep your own copy OUTSIDE the repo;
#    build-and-push.sh stages it into this build context for the build and
#    removes it afterwards. See README ("Supplying the installer").
#    Tested: 3.9.141.259.
# ---------------------------------------------------------------------------
COPY picasa39-setup.exe /tmp/picasa39-setup.exe
RUN /install-picasa.sh && rm -f /tmp/picasa39-setup.exe

# ---------------------------------------------------------------------------
# 4. Runtime configuration.
# ---------------------------------------------------------------------------
ENV APP_NAME=Picasa \
    DISPLAY=:0 \
    DISPLAY_WIDTH=1920 \
    DISPLAY_HEIGHT=1080 \
    WINEARCH=win32 \
    WINEPREFIX=/config/wine \
    WINEDEBUG=-all \
    WINEDLLOVERRIDES=mscoree=d;mshtml=d \
    TZ=UTC \
    USER_ID=1000 \
    GROUP_ID=1000

EXPOSE 5800
VOLUME ["/config", "/storage"]

ENTRYPOINT ["/entrypoint.sh"]
