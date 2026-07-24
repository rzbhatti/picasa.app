#!/usr/bin/env bash
# Shared helpers/config for the Picasa app. Sourced by setup.sh / run.sh / stop.sh.

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$APP_DIR/picasa.conf"
TARFILE="$APP_DIR/picasa-image.tar"
IMAGE="${IMAGE:-picasa-app:latest}"
# Public recovery source: used if the bundled tar is missing or corrupt.
REGISTRY_IMAGE="${REGISTRY_IMAGE:-quay.io/wine_apps/picasa-3.9:latest}"

expand_path() {                        # expand a leading ~ to $HOME
    local p="$1"
    case "$p" in
        "~")   p="$HOME" ;;
        "~/"*) p="$HOME/${p#\~/}" ;;
    esac
    printf '%s' "$p"
}

drive_root() {                         # print the mount point that contains "$1"
    df -P "$1" 2>/dev/null | awk 'NR==2 { $1=$2=$3=$4=$5=""; sub(/^ +/,""); print }'
}

subpath_on_drive() {                   # if "$1" is under mount "$2", print the sub-path
    local dir="${1%/}" root="${2%/}"
    case "$dir/" in
        "$root/"*) printf '%s' "${dir#$root/}" ;;
        *)         printf '' ;;
    esac
}

locate_picasadb() {                    # print dirs that hold a Picasa database under "$1"
    find "$1" -maxdepth 7 -type d -path '*/Google/Picasa2' 2>/dev/null \
        | sed 's#/Google/Picasa2$##' | sort -u
}

write_conf() {
    cat > "$CONF" <<EOF
# Picasa configuration (created/updated automatically).
# Run './setup.sh' (or './run.sh --reconfigure') to change these.
PHOTOS_DIR="$PHOTOS_DIR"
PHOTOS_ONDRIVE="$PHOTOS_ONDRIVE"
PICASADB_DIR="$PICASADB_DIR"
PICASADB_ONDRIVE="$PICASADB_ONDRIVE"
DISPLAY_WIDTH="${DISPLAY_WIDTH:-1920}"
DISPLAY_HEIGHT="${DISPLAY_HEIGHT:-1080}"
EOF
}

load_conf() { set -a; . "$CONF"; set +a; }

# Non-interactive path healing after a drive is moved to a new mount point.
# Returns 0 if both locations resolve, 1 if setup/asking is needed.
resolve_paths() {
    local app_drive changed=0
    app_drive="$(drive_root "$APP_DIR")"

    # Pictures: prefer the on-drive relative location, else the saved absolute one.
    if [ -n "${PHOTOS_ONDRIVE:-}" ] && [ -d "$app_drive/$PHOTOS_ONDRIVE" ]; then
        [ "$PHOTOS_DIR" != "$app_drive/$PHOTOS_ONDRIVE" ] && { PHOTOS_DIR="$app_drive/$PHOTOS_ONDRIVE"; changed=1; }
    elif [ ! -d "${PHOTOS_DIR:-}" ]; then
        return 1
    fi

    # Database: on-drive relative → saved absolute → single search hit → give up.
    if [ -n "${PICASADB_ONDRIVE:-}" ] && [ -d "$app_drive/$PICASADB_ONDRIVE" ]; then
        [ "$PICASADB_DIR" != "$app_drive/$PICASADB_ONDRIVE" ] && { PICASADB_DIR="$app_drive/$PICASADB_ONDRIVE"; changed=1; }
    elif [ ! -d "${PICASADB_DIR:-}" ]; then
        local hits n
        hits="$(locate_picasadb "$app_drive")"
        n="$(printf '%s\n' "$hits" | grep -c . || true)"
        if [ "$n" = "1" ]; then
            PICASADB_DIR="$hits"; changed=1
        else
            return 1
        fi
    fi

    PHOTOS_ONDRIVE="$(subpath_on_drive "$PHOTOS_DIR" "$app_drive")"
    PICASADB_ONDRIVE="$(subpath_on_drive "$PICASADB_DIR" "$app_drive")"
    [ "$changed" -eq 1 ] && write_conf
    return 0
}

# Make sure $IMAGE is available in the engine. Order:
#   1. already loaded            -> use it
#   2. bundled tar (if valid)    -> load it
#   3. public registry fallback  -> pull, tag locally, and rebuild the offline tar
ensure_image() {
    if $ENGINE image inspect "$IMAGE" >/dev/null 2>&1; then
        return 0
    fi

    if [ -f "$TARFILE" ]; then
        if tar tf "$TARFILE" >/dev/null 2>&1; then
            echo "==> Loading the bundled application image (one-time, please wait)…"
            if $ENGINE load -i "$TARFILE" >/dev/null 2>&1 && $ENGINE image inspect "$IMAGE" >/dev/null 2>&1; then
                return 0
            fi
            echo "WARN: bundled image failed to load (corrupt?). Falling back to download."
        else
            echo "WARN: bundled image archive is unreadable (corrupt/incomplete). Falling back to download."
        fi
    else
        echo "==> No bundled image present."
    fi

    echo "==> Downloading image from ${REGISTRY_IMAGE} …"
    if ! $ENGINE pull "$REGISTRY_IMAGE"; then
        echo "ERROR: could not download the image from ${REGISTRY_IMAGE}." >&2
        return 1
    fi
    $ENGINE tag "$REGISTRY_IMAGE" "$IMAGE"

    # Restore the offline copy so future runs work without a network.
    echo "==> Restoring offline copy (picasa-image.tar) …"
    if ! $ENGINE save "$IMAGE" -o "$TARFILE" 2>/dev/null; then
        echo "WARN: could not rewrite picasa-image.tar (not fatal; the image is loaded)."
    fi
    return 0
}

pick_engine() {
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        ENGINE=docker
    elif command -v podman >/dev/null 2>&1; then
        ENGINE=podman
    else
        echo "ERROR: Docker or Podman is required, but neither is available/running." >&2
        return 1
    fi
}

# On macOS, the Docker/Podman Linux VM (Colima, Docker Desktop) registers a
# 'qemu-i386' binfmt handler that hijacks all 32-bit x86 binaries and runs them
# under emulation. Picasa is a 32-bit app, so this makes Wine crawl and noVNC
# shows a black screen. The VM's amd64 kernel runs i386 natively, so we drop the
# emulator. It gets re-registered every time the VM restarts, hence we heal it on
# each launch. No-op on native Linux and when the handler isn't present.
heal_native_i386() {
    [ "$(uname -s 2>/dev/null)" = "Darwin" ] || return 0
    local info
    info="$($ENGINE run --rm --privileged tonistiigi/binfmt 2>/dev/null)" || return 0
    case "$info" in
        *qemu-i386*)
            echo "==> Enabling native 32-bit execution (removing qemu-i386 emulator)…"
            $ENGINE run --rm --privileged tonistiigi/binfmt --uninstall qemu-i386 >/dev/null 2>&1 \
                || echo "    (note: couldn't remove qemu-i386; Picasa may run slowly)"
            ;;
    esac
}

pick_compose() {
    COMPOSE_FILES=(-f "$APP_DIR/docker-compose.yml")
    if [ "$ENGINE" = docker ]; then
        if docker compose version >/dev/null 2>&1; then COMPOSE=(docker compose)
        elif command -v docker-compose >/dev/null 2>&1; then COMPOSE=(docker-compose)
        else echo "ERROR: 'docker compose' not found." >&2; return 1; fi
    else
        COMPOSE_FILES+=(-f "$APP_DIR/docker-compose.podman.yml")
        if podman compose version >/dev/null 2>&1; then COMPOSE=(podman compose)
        elif command -v podman-compose >/dev/null 2>&1; then COMPOSE=(podman-compose)
        else echo "ERROR: 'podman compose' / 'podman-compose' not found." >&2; return 1; fi
    fi
}
