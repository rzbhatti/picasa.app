#!/usr/bin/env bash
# Build the Picasa image and push it to its Quay.io repo.
#
# The published repo is PUBLIC, so pulling needs no login; only pushing does.
#
# Requires your own copy of the Picasa installer. It is proprietary, so it is
# kept OUTSIDE this repository -- by default two levels up, alongside the repo:
#
#     <parent>/picasa39-setup.exe        <- the installer lives here
#     <parent>/picasa.app/build/         <- this script
#
# It is copied into the build context only for the duration of the build and
# removed again afterwards, so it never lands in a commit (see README).
#
# Usage:
#   docker login quay.io           # (once) then:
#   ./build-and-push.sh
#
# Override the target with env vars if needed:
#   IMAGE=quay.io/wine_apps/picasa-3.9 VERSION=3.9.141.259 ./build-and-push.sh
#   INSTALLER=/path/to/picasa39-setup.exe ./build-and-push.sh
#
# Nothing is pushed unless you are logged in to the target registry.
set -euo pipefail

cd "$(dirname "$0")"

IMAGE="${IMAGE:-quay.io/wine_apps/picasa-3.9}"   # registry/namespace/repo
VERSION="${VERSION:-3.9.141.259}"                # extra immutable tag
REGISTRY="${IMAGE%%/*}"                           # e.g. quay.io

# --- 1. Verify Docker is available -------------------------------------------
if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon is not running or not reachable." >&2
    exit 1
fi

# --- 1b. Locate the (non-redistributable) installer, kept outside the repo ----
# Searched in order: $INSTALLER, then the usual names in the repo's parent dir.
if [ -n "${INSTALLER:-}" ]; then
    CANDIDATES=("$INSTALLER")
else
    CANDIDATES=(../../picasa39-setup.exe ../../picasa-3-9-141-259.exe)
fi

SRC=""
for c in "${CANDIDATES[@]}"; do
    [ -f "$c" ] && { SRC="$c"; break; }
done

if [ -z "$SRC" ]; then
    echo "ERROR: Picasa installer not found." >&2
    echo "  Looked for: ${CANDIDATES[*]}" >&2
    echo "  (relative to $(pwd))" >&2
    echo >&2
    echo "  Picasa 3.9 is proprietary and is deliberately NOT in this repository." >&2
    echo "  Put your own copy next to the repo, e.g.:" >&2
    echo "      \$(dirname \$(pwd))/../picasa39-setup.exe" >&2
    echo "  or point at it explicitly:  INSTALLER=/path/to/setup.exe $0" >&2
    echo "  Tested build: 3.9.141.259 (sha256 482c1a54...e73e08) -- see README." >&2
    echo >&2
    echo "  To only RUN Picasa you do not need this at all -- use ../run.sh," >&2
    echo "  which pulls the prebuilt public image." >&2
    exit 1
fi

# Stage it into the build context just for this build; always clean it up so a
# proprietary binary is never left sitting inside the repo.
STAGED="picasa39-setup.exe"
STAGED_BY_US=0
if [ ! -f "$STAGED" ]; then
    echo "==> Staging installer from ${SRC} (removed after the build)"
    cp "$SRC" "$STAGED"
    STAGED_BY_US=1
fi
cleanup() { [ "$STAGED_BY_US" -eq 1 ] && rm -f "$STAGED"; }
trap cleanup EXIT

# --- 2. Verify we are logged in to the target registry -----------------------
CONFIG="${DOCKER_CONFIG:-$HOME/.docker}/config.json"
if ! grep -q "\"${REGISTRY}\"" "$CONFIG" 2>/dev/null; then
    echo "ERROR: You do not appear to be logged in to ${REGISTRY}." >&2
    echo "  Run:  docker login ${REGISTRY}" >&2
    echo "  (then re-run this script)" >&2
    exit 1
fi

# --- 3. Build ----------------------------------------------------------------
echo "==> Building ${IMAGE}:latest (and :${VERSION})"
docker build -t "${IMAGE}:latest" -t "${IMAGE}:${VERSION}" .

# --- 4. Push -----------------------------------------------------------------
echo "==> Pushing ${IMAGE}:latest"
docker push "${IMAGE}:latest"
echo "==> Pushing ${IMAGE}:${VERSION}"
docker push "${IMAGE}:${VERSION}"

echo "==> Done. Pushed ${IMAGE}:latest and ${IMAGE}:${VERSION}"
echo "    On any target machine (after 'docker login ${REGISTRY}'):  ./run.sh"
