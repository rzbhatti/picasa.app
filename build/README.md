# Building the Picasa image

> **You almost certainly don't need this.** To *use* Picasa, go up one level and
> run [`../run.sh`](../) — it pulls the prebuilt image for you. This folder is for
> rebuilding, auditing or republishing the image itself.

This builds the Docker image that bundles **Google Picasa 3.9** (a 32-bit Windows
application) with **Wine**, and streams its GUI to a web browser via **noVNC**.
Because it's a container, it runs identically on **macOS and Linux** — no local
Wine install, no X server setup.

The image is built from `debian:bookworm-slim` using only official Debian
packages (Wine, Xvfb, x11vnc, noVNC/websockify, openbox, supervisor). Picasa is
installed silently at build time and launches automatically when the container
starts.

```
Browser ──http://localhost:5800──▶ noVNC ─▶ x11vnc ─▶ Xvfb (:0) ─▶ Picasa (Wine)
```

---

## Prerequisites

- **Docker + Docker Compose** installed and running on the target machine.
  A **native Linux/amd64 host is strongly recommended** — see
  [Performance](#performance-native-linux-vs-mac) below.
- **To run the prebuilt image:** nothing else. **`quay.io/wine_apps/picasa-3.9`**
  is a public repository and pulls anonymously — no `docker login` needed.
- **To build the image yourself:** your own copy of the Picasa 3.9 installer,
  kept **outside** this repository — see
  [Supplying the installer](#supplying-the-installer).
- **To push a rebuilt image:** write access to the target registry repo, and
  `docker login quay.io`.
- `curl` (used by `run.sh` to detect readiness — preinstalled on macOS and most
  Linux).

---

## Supplying the installer

Picasa 3.9 is **discontinued Google proprietary software**. This repository
contains only the packaging — Dockerfile, scripts and docs — and deliberately
does **not** redistribute the installer.

Keep your own copy **outside the repository**, in the folder that contains it:

```
picasa-wine/                     <- any parent folder you like
├── picasa39-setup.exe           <- your installer lives HERE, outside git
└── picasa.app/                  <- this repository
    └── build/                   <- this folder
```

`build-and-push.sh` finds it there, copies it into the build context for the
build only, and deletes the copy afterwards — so it never reaches a commit.
`*.exe` is also gitignored as a safety net. To keep it somewhere else:

```bash
INSTALLER=/path/to/picasa39-setup.exe ./build-and-push.sh
```

The build was developed against **Picasa 3.9 build 141.259**. Verify what you
have with:

```bash
shasum -a 256 ../../picasa39-setup.exe
# 482c1a547d8d3aa25ee446d30ea986de63ef8c8d68b8d1109dd3d9b714e73e08
```

A different build will very likely still work (the install is a stock NSIS `/S`),
but only that one is tested. If you just want to *run* Picasa rather than build
it, use the prebuilt public image and skip this entirely.

---

## First-time setup

You only do this once, on the machine that builds and publishes the image
(ideally a native Linux/amd64 host).

1. **Supply the installer** outside the repo — see
   [Supplying the installer](#supplying-the-installer). The build script stops
   with a clear message if it can't find it.

2. **Log in to Quay.io** (only needed to *push*; pulling is anonymous):
   ```bash
   docker login quay.io
   ```

3. **Build and push the image:**
   ```bash
   cd build
   ./build-and-push.sh
   ```
   This builds and pushes `quay.io/wine_apps/picasa-3.9:latest` (and an
   immutable `:3.9.141.259` tag). Override the target with
   `IMAGE=... VERSION=... ./build-and-push.sh` if needed. The script refuses to
   push unless you're logged in to the registry.

   > The image has already been published to
   > `quay.io/wine_apps/picasa-3.9` — you only need to rebuild/push if you
   > change something.

---

## Testing the image from this folder

A maintainer-side smoke test: pull (or use your freshly built image) and run it
against throwaway `build/config` and `build/photos` folders, without touching the
locations your real bundle uses. No registry login required — the image is public.

```bash
cd build
./run.sh
```

`run.sh` pulls the latest image, starts the container (named `picasa`), waits for
the web UI, and prints:

```
Open http://localhost:5800
```

Open that URL in your browser and Picasa is right there.

> **First launch:** the very first time Picasa runs it shows a one-time
> **"Usage Statistics"** prompt (and may show a EULA). Click through it in the
> browser — your choice is saved into `./config`, so it won't appear again on
> later runs. To point Picasa at your photos, use **File → Add Folder to Picasa**
> and browse to drive **`P:\`** (which is your `./photos` folder).

To stop it:
```bash
docker compose down          # or: docker stop picasa
```

### Running it as an end user (recommended)

Everything above is the *build/maintainer* path, and it keeps photos and config
in fixed `config/` and `photos/` folders inside this build folder.

For actually **using** Picasa — including from an external drive, moving between
machines, and with Podman — use the bundle one level up, [`../run.sh`](../). It
asks where your pictures and database live, remembers it, re-finds them if the
drive mounts elsewhere, and can run fully offline from `picasa-image.tar`. It
persists Picasa's catalog to a folder you choose (via `PICASA_DATA_DIR` → the
`AppLocalDataPath` registry key), so photos and catalog travel together.

### Purely local (no registry)

To build and run without pulling from Quay:
```bash
docker build -t picasa-local:test .
IMAGE=picasa-local:test docker compose up -d   # or uncomment `build: .` in the compose file
```

---

## How persistence works

Two host folders are bind-mounted into the container, so **everything survives**
container restarts, upgrades, and even `docker compose down`. Together they hold
Picasa's complete catalog:

| Host folder | Container path    | Holds |
|-------------|-------------------|-------|
| `./config`  | `/config`         | The Wine prefix (`/config/wine`). Inside it, Picasa stores its data under the Windows profile: `drive_c/users/app/AppData/Local/Google/Picasa2` (the database/index `.pmp`+`.db` files, thumbnails, and `contacts.xml` = face→name mappings) and `…/Picasa2Albums` (albums). Picasa's preferences live in the Wine registry (`/config/wine/user.reg`), also here. |
| `./photos`  | `/storage/photos` | Your actual photos, **read-write** — plus the per-folder hidden `.picasa.ini` sidecar files Picasa writes alongside them (crops, non-destructive edits, per-photo face rectangles, star ratings). |

Where each piece of your catalog lives (both volumes persist, so all of it is
retained across sessions):

- **Photo index / thumbnails / DB** → `/config` (`…/Google/Picasa2`)
- **Albums** → `/config` (`…/Google/Picasa2Albums`)
- **Face names (who each face is)** → `/config` (`…/Picasa2/contacts.xml`)
- **Face rectangles + non-destructive edits + star ratings** → `/photos`
  (each folder's hidden `.picasa.ini`)
- **App preferences/settings** → `/config` (`user.reg` in the Wine prefix)

- On **first run**, the container seeds `/config/wine` from a pristine copy baked
  into the image (`/opt/wine-defaults`). Picasa then creates its database under
  that persisted prefix the first time it runs, and updates it in place after.
- Inside Picasa, your photos appear on drive **`P:`** (and also under `Z:\storage\photos`,
  since Wine maps `Z:` to the container root). Point Picasa's folder manager at
  `P:\` to import them.
- To start completely fresh, stop the container and delete `./config` (your
  photos in `./photos` are untouched).

---

## Upgrading

Rebuild and push a new image, then on each machine:
```bash
./run.sh    # pulls latest, recreates the container
```
Your `./config` and `./photos` are preserved across upgrades.

---

## Troubleshooting

### Picasa doesn't appear (blank desktop / grey screen)
1. Check the logs:
   ```bash
   docker logs -f picasa
   ```
   Look for `Launching Picasa:` and any Wine errors after it.
2. Check the service states:
   ```bash
   docker exec -it picasa supervisorctl -c /etc/supervisor/supervisord.conf status
   ```
   All of `xvfb`, `openbox`, `x11vnc`, `novnc`, `picasa` should be `RUNNING`.
3. Restart just Picasa:
   ```bash
   docker exec -it picasa supervisorctl -c /etc/supervisor/supervisord.conf restart picasa
   ```
4. If it still fails, the Wine prefix may be corrupt — stop the container, delete
   `./config`, and start again (it re-seeds from the baked prefix).

### Get a shell into the container to debug Wine
```bash
docker exec -it picasa bash

# inside the container, drive Wine directly against the persistent prefix:
export DISPLAY=:0
export WINEPREFIX=/config/wine
export WINEARCH=win32
wine --version
winecfg                      # opens on the noVNC desktop
wine "$(cat /config/wine/picasa-exe-path.txt)"   # launch Picasa manually
```
Wine logs are quiet by default (`WINEDEBUG=-all`). For a verbose run:
```bash
WINEDEBUG=+all wine "$(cat /config/wine/picasa-exe-path.txt)" 2>&1 | head -100
```

### The Picasa window is cut off / I want a bigger (or smaller) resolution
The noVNC resolution is the Xvfb screen size, controlled by two env vars.
Edit `docker-compose.yml`:
```yaml
    environment:
      - DISPLAY_WIDTH=2560
      - DISPLAY_HEIGHT=1440
```
then recreate the container:
```bash
docker compose up -d --force-recreate
```
(In the noVNC toolbar you can also enable **Settings → Scaling Mode → Local
Scaling** to fit the remote screen to your browser window.)

### Fonts look wrong / text is missing
The image installs **Liberation fonts** (`fonts-liberation`, from Debian main) —
metric-compatible substitutes for Arial/Times/Courier that Wine uses in place of
the Microsoft core fonts Picasa expects. This resolves Picasa's most common text
issues without any build-time font download.

If you specifically want the genuine Microsoft core fonts (e.g. exact metrics),
get a shell (above) and install them into the persistent prefix — note this
downloads from a third-party mirror at runtime:
```bash
apt-get update && apt-get install -y cabextract
# then fetch + register corefonts manually, or install `winetricks` from
# Debian's contrib component and run: WINEPREFIX=/config/wine winetricks -q corefonts
docker exec -it picasa supervisorctl -c /etc/supervisor/supervisord.conf restart picasa
```

### Port 5800 is already in use
Change the host side of the mapping in `docker-compose.yml`, e.g.
`- "5900:5800"`, then browse to `http://localhost:5900`.

---

## Publishing commands (quick reference)

The image is published at **`quay.io/wine_apps/picasa-3.9`**. To rebuild/republish:

```bash
cd build
docker login quay.io       # needed only to PUSH (pulling is anonymous)
./build-and-push.sh        # build + push :latest and :3.9.141.259
# then, on any target machine:
./run.sh                   # pull + run, prints the URL
```

---

## Performance: native Linux vs Mac

Picasa is a **32-bit** app, so the image runs a 32-bit Wine engine.

- **Native Linux/amd64 host** (a PC, server, or amd64 cloud VM): 32-bit code runs
  natively — Picasa performs normally. **This is the recommended way to run it.**
- **Docker Desktop for Mac:** Docker's Linux VM routes 32-bit (i386) binaries
  through `qemu-i386` emulation. The noVNC stream itself stays responsive (it's
  64-bit/native), but Picasa's own work — image decode, thumbnailing, library
  indexing, and face detection — is emulated and **noticeably slow**, especially
  the first-time index of a large library. Fine for a quick look; use a native
  Linux host for a real photo collection.

The image is identical on both; only the Mac pays the emulation tax.

---

## Notes on the build

- **Silent install:** the Picasa 3.9.141.259 installer is an NSIS package; it is
  installed non-interactively with the `/S` flag during `docker build`, running
  under a virtual framebuffer (`xvfb-run`) since there's no display at build time.
- **32-bit:** Picasa is a 32-bit app, so the image enables the `i386`
  architecture and creates a `win32` Wine prefix (`WINEARCH=win32`).
- **Image size:** the installer `.exe` is removed in the same build layer it's
  added, and Wine caches + apt lists are cleared, to keep the final image lean
  (~3 GB, dominated by the Wine i386 runtime).
- **No third-party base image:** the Wine + noVNC stack is built directly on
  `debian:bookworm-slim` with official Debian packages, rather than on one of the
  community "Wine in Docker" images. That keeps the whole supply chain to Debian
  main and makes every layer auditable from this Dockerfile.
