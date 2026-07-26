#!/usr/bin/env bash
# Pull the latest Picasa image and start it.
#
# The image repo is public, so no docker login is required.
#
# Usage:
#   ./run.sh
#
# Override the image with:  IMAGE=quay.io/wine_apps/picasa-3.9:3.9.141.259 ./run.sh
set -euo pipefail

cd "$(dirname "$0")"

IMAGE="${IMAGE:-quay.io/wine_apps/picasa-3.9:latest}"
export IMAGE

# Pick the compose command (v2 plugin or legacy binary).
if docker compose version >/dev/null 2>&1; then
    COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE="docker-compose"
else
    echo "ERROR: docker compose is not available." >&2
    exit 1
fi

mkdir -p config photos

# --- Pull the latest image (best-effort; a local image still runs) -----------
echo "==> Pulling ${IMAGE}"
docker pull "${IMAGE}" || echo "WARN: pull failed; using the local image if present."

# --- Start -------------------------------------------------------------------
echo "==> Starting the picasa container"
$COMPOSE up -d

# --- Wait for noVNC to answer on 5800 ----------------------------------------
echo -n "==> Waiting for noVNC on port 5800 "
for i in $(seq 1 60); do
    if curl -fsS -o /dev/null "http://localhost:5800/"; then
        echo
        echo "==> Ready.  Open http://localhost:5800"
        exit 0
    fi
    echo -n "."
    sleep 2
done

echo
echo "WARN: port 5800 did not respond within ~2 minutes." >&2
echo "      Check logs with:  docker logs -f picasa" >&2
exit 1
