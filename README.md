# Picasa (portable)

A ready-to-run, containerized copy of **Google Picasa 3.9** that you open in your
**web browser**. It runs the same on **macOS and Linux**, from a **local folder or
an external drive** — nothing is installed on the computer itself.

Picasa runs inside a container (via Wine) and its screen is streamed to your
browser. Your **pictures and your Picasa catalog live in folders you choose**, so
your albums, edits and face tags stay with your photos.

---

## Requirements

- **Docker** (Docker Desktop on macOS/Windows, or Docker Engine on Linux) **or
  Podman**, installed and running.
- A web browser.

That's all — no Wine, no Picasa installer, no setup on the host.

---

## Quick start

Open a terminal in this folder and run:

```bash
./setup.sh     # asks where your pictures are and where to keep the database
./run.sh       # starts Picasa, then prints a link
```

When it says **`Picasa is ready -> http://localhost:5800`**, open that address in
your browser.

To stop it:

```bash
./stop.sh
```

> `run.sh` will run `setup.sh` automatically the first time, so you can also just
> run `./run.sh`.

---

## First launch

- Picasa shows a one-time **"Usage Statistics"** prompt — click either button.
- To load your photos: **File ▸ Add Folder to Picasa**, then open drive **`P:\`**
  — that is the pictures folder you chose during setup. Add the subfolders you
  want Picasa to watch.

---

## Where your data is stored

You choose two locations during setup:

| You choose | What goes there | Notes |
|------------|-----------------|-------|
| **Pictures folder** | Your photos & videos, plus per-photo edits/crops/ratings and face boxes (in hidden `.picasa.ini` files) | Read + write. Appears in Picasa as drive `P:\`. |
| **Database folder** | Picasa's index, thumbnails, **albums**, and **face names** (`Google/Picasa2` and `Google/Picasa2Albums`) | This is your catalog. Keep it to preserve your organizing work. |

Everything Picasa creates to organize your pictures lives in those two folders, so
it persists between sessions and travels with them.

The only thing kept per-computer is Picasa's internal "Windows environment"
(needed by Wine); it is recreated automatically and needs no attention.

---

## Using it from an external drive / moving between computers

Put this whole folder on the drive (ideally alongside your pictures and database
folders). Then on any computer:

```bash
./run.sh
```

If the drive mounts at a different path on the new computer, the app **finds your
pictures and database automatically**. If it can't (for example they're on a
different drive), it searches for your Picasa database and, failing that, simply
asks you again. You can also re-point things any time:

```bash
./run.sh --reconfigure      # or: ./setup.sh
```

If the folder includes `picasa-image.tar`, the app works **fully offline** — it
loads that bundled image on first run, so no download or login is required. If
that file is ever **missing or damaged**, the app automatically downloads the
image from its public registry and **rebuilds `picasa-image.tar`**, so offline use
is restored for next time.

---

## Performance

Picasa is a 32-bit application. On a **Linux computer with an Intel/AMD (amd64)
CPU** it runs at full, native speed. On **macOS (via Docker Desktop)** the 32-bit
code is emulated, so Picasa's heavy tasks — building thumbnails, indexing a large
library, face detection — run noticeably slower (the window itself stays
responsive). For a big photo library, a Linux/amd64 machine gives the best
experience; the same folder works in both places.

---

## Troubleshooting

- **Nothing shows / grey screen:** check the logs —
  `docker logs -f picasa` (or `podman logs -f picasa`). Then check services:
  `docker exec -it picasa supervisorctl -c /etc/supervisor/supervisord.conf status`
  (all should be `RUNNING`).
- **"Permission denied" writing to your folders (Linux):** the container runs as
  your user ID by default. If your files are owned by a different user, adjust
  `USER_ID`/`GROUP_ID` in `docker-compose.yml` and run `./stop.sh && ./run.sh`.
- **Window is cut off / want a bigger screen:** edit `DISPLAY_WIDTH` /
  `DISPLAY_HEIGHT` in `picasa.conf`, then `./stop.sh && ./run.sh`. In the browser
  toolbar you can also enable **Settings ▸ Scaling ▸ Local Scaling**.
- **Port 5800 already in use:** change the left number of `"5800:5800"` in
  `docker-compose.yml` (e.g. `"5900:5800"`) and open `http://localhost:5900`.
- **Start over:** stop the app and delete your database folder — your photos are
  untouched; Picasa rebuilds the catalog from them and the `.picasa.ini` files.

---

## What's in this folder

| File | Purpose |
|------|---------|
| `setup.sh` | Configure the pictures & database locations |
| `run.sh` | Start Picasa (auto-configures, auto-relocates on a moved drive) |
| `stop.sh` | Stop Picasa |
| `docker-compose.yml` | Container definition |
| `docker-compose.podman.yml` | Podman-only adjustment (used automatically) |
| `picasa-image.tar` | *(optional)* the application image, for offline use |
| `lib.sh` | Shared helper functions used by the scripts |
| `picasa.conf` | *(created by setup)* your saved locations |
