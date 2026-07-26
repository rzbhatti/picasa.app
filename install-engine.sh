#!/usr/bin/env bash
# Install a container engine (Docker or Podman) so Picasa can run.
#
#   ./install-engine.sh          detect the system, offer the options, install
#
# Nothing is installed without asking: every command that changes your system is
# printed and confirmed first. run.sh offers to call this automatically when no
# engine is found, but it is safe to run on its own.
#
# Covers macOS (via Homebrew) and Linux (apt / dnf / pacman / zypper). On Windows
# it prints what to do, since this bundle's scripts need Git Bash or WSL anyway.
set -euo pipefail
cd "$(dirname "$0")"

# --- small helpers -----------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

ask() {                                  # ask "question"  -> 0 = yes
    local reply
    printf '%s [y/N] ' "$1"
    # A read we cannot perform counts as "no": never assume consent.
    read -r reply </dev/tty || return 1
    case "$reply" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

# Read a menu answer into CHOICE. Returns non-zero if there is no terminal to ask
# on -- callers must abort in that case rather than assume a default, or a
# non-interactive run would start installing things nobody agreed to.
read_choice() {
    printf '%s ' "$1"
    read -r CHOICE </dev/tty && return 0
    echo >&2
    echo "ERROR: this script needs an interactive terminal to ask which engine" >&2
    echo "       you want. Run it directly:  ./install-engine.sh" >&2
    return 1
}

# Show a command, get consent, then run it. Everything that modifies the system
# goes through here, so nothing is a surprise.
run_step() {
    echo
    echo "    $*"
    echo
    ask "  Run this?" || { echo "  Skipped."; return 1; }
    "$@"
}

already_have_engine() {
    if have docker && docker info >/dev/null 2>&1; then
        echo "==> Docker is already installed and running. Nothing to do."
        echo "    Start Picasa with:  ./run.sh"
        return 0
    fi
    if have podman && podman info >/dev/null 2>&1; then
        echo "==> Podman is already installed and running. Nothing to do."
        echo "    Start Picasa with:  ./run.sh"
        return 0
    fi
    return 1
}

# =============================================================================
# macOS
# =============================================================================
install_macos() {
    echo "==> Detected macOS ($(uname -m))."
    echo

    if ! have brew; then
        cat <<'EOF'
Homebrew is the simplest way to install a container engine on macOS, and it is
not installed yet. Install it first with:

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

Then run this script again.

Alternatively, download Docker Desktop directly:
    https://www.docker.com/products/docker-desktop/
EOF
        return 1
    fi

    cat <<'EOF'
Choose a container engine:

  1) Colima + Docker CLI   (recommended — lightweight, no GUI, free for any use)
  2) Docker Desktop        (GUI app; check Docker's licence terms for business use)
  3) Podman                (daemonless alternative)

EOF
    read_choice 'Which? [1/2/3]' || return 1

    case "${CHOICE:-1}" in
        1)
            run_step brew install colima docker docker-compose || return 1
            start_colima
            ;;
        2)
            run_step brew install --cask docker || return 1
            echo
            echo "==> Docker Desktop is installed. Open it once from Applications so it"
            echo "    can finish setting up, then run ./run.sh"
            ;;
        3)
            run_step brew install podman podman-compose || return 1
            if ! podman machine inspect >/dev/null 2>&1; then
                run_step podman machine init || return 1
            fi
            run_step podman machine start || true
            ;;
        *)  echo "Unrecognised choice; nothing installed." >&2; return 1 ;;
    esac
}

# Colima runs the Linux VM that Docker talks to. It only exposes host folders it
# was told to mount, and by default that is just your home directory — so if this
# bundle (or your photos) live on an external drive, that drive must be mounted or
# Picasa sees an empty P:\. We work that out here and start the VM accordingly.
start_colima() {
    local drive mount_args=()
    drive="$(df -P . 2>/dev/null | awk 'NR==2 { $1=$2=$3=$4=$5=""; sub(/^ +/,""); print }')"

    if [ -n "$drive" ] && [ "$drive" != "/" ] && case "$PWD" in "$HOME"/*) false ;; *) true ;; esac; then
        echo
        echo "==> This folder is on '$drive', which is outside your home directory."
        echo "    Colima must share that drive or Picasa will see an empty P:\\ drive."
        mount_args=(--mount "$drive:w")
    fi

    if colima status >/dev/null 2>&1; then
        echo "==> Colima is already running."
        if [ ${#mount_args[@]} -gt 0 ]; then
            echo "    It may need restarting to pick up '$drive':"
            run_step colima stop || true
            run_step colima start "${mount_args[@]}" || return 1
        fi
    else
        run_step colima start "${mount_args[@]}" || return 1
    fi
}

# =============================================================================
# Linux
# =============================================================================
install_linux() {
    local id_like="" pretty="Linux"
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        id_like="${ID:-} ${ID_LIKE:-}"
        pretty="${PRETTY_NAME:-Linux}"
    fi
    echo "==> Detected $pretty ($(uname -m))."

    local sudo=""
    if [ "$(id -u)" -ne 0 ]; then
        have sudo || { echo "ERROR: need root or sudo to install packages." >&2; return 1; }
        sudo="sudo"
    fi

    cat <<'EOF'

Choose a container engine:

  1) Podman   (recommended on Linux — rootless, so it works immediately with no
              group changes and no re-login)
  2) Docker   (needs a service and adding you to the 'docker' group, which only
              takes effect after you log out and back in)

EOF
    read_choice 'Which? [1/2]' || return 1
    local engine
    case "${CHOICE:-1}" in
        1) engine=podman ;;
        2) engine=docker ;;
        *) echo "Unrecognised choice; nothing installed." >&2; return 1 ;;
    esac

    # Package names differ per distro family.
    local pkgs=()
    case " $id_like " in
        *" debian "*|*" ubuntu "*)
            if [ "$engine" = podman ]; then pkgs=(podman podman-compose)
            else pkgs=(docker.io docker-compose-v2); fi
            run_step $sudo apt-get update || return 1
            run_step $sudo apt-get install -y "${pkgs[@]}" || return 1
            ;;
        *" fedora "*|*" rhel "*|*" centos "*)
            if [ "$engine" = podman ]; then pkgs=(podman podman-compose)
            else pkgs=(moby-engine docker-compose); fi
            run_step $sudo dnf install -y "${pkgs[@]}" || return 1
            ;;
        *" arch "*)
            if [ "$engine" = podman ]; then pkgs=(podman podman-compose)
            else pkgs=(docker docker-compose); fi
            run_step $sudo pacman -S --needed "${pkgs[@]}" || return 1
            ;;
        *" suse "*|*" opensuse "*)
            if [ "$engine" = podman ]; then pkgs=(podman podman-compose)
            else pkgs=(docker docker-compose); fi
            run_step $sudo zypper install -y "${pkgs[@]}" || return 1
            ;;
        *)
            cat <<EOF

Your distribution wasn't recognised, so install $engine with your package
manager, then run ./run.sh — for example:

    <your package manager> install $engine

Podman is usually the easier choice: it is rootless, so it needs no service
and no group changes.
EOF
            return 1
            ;;
    esac

    # Docker needs its daemon running and the user in the docker group.
    if [ "$engine" = docker ]; then
        have systemctl && run_step $sudo systemctl enable --now docker || true
        if ! id -nG "${USER:-$(id -un)}" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
            echo
            echo "==> To use Docker without sudo you must be in the 'docker' group."
            run_step $sudo usermod -aG docker "${USER:-$(id -un)}" || true
            echo
            echo "  IMPORTANT: log out and back in (or reboot) for that to take effect,"
            echo "             then run ./run.sh"
            return 0
        fi
    fi
}

# =============================================================================
# Windows (Git Bash / MSYS / Cygwin / WSL)
# =============================================================================
install_windows() {
    cat <<'EOF'
==> Detected Windows.

Worth knowing first: Picasa 3.9 is itself a Windows application. On Windows you
do NOT need this container at all — installing Picasa directly is simpler and
faster, and you can skip everything below.

If you still want the containerized version (for example to keep one identical
setup across Windows, macOS and Linux), you need two things:

  1. Docker Desktop, with the WSL2 backend:

         winget install Docker.DockerDesktop

     (or download it from https://www.docker.com/products/docker-desktop/)
     Then start Docker Desktop once and let it enable WSL2 if it asks.

  2. A place to run these scripts. They are bash scripts, so use WSL2:

         wsl --install                  # once, if you have no WSL distro yet

     Then open your WSL distro, cd to this folder, and run ./run.sh
     In Docker Desktop, enable Settings > Resources > WSL integration for
     that distro so it can reach Docker.

Note that Windows file paths appear as /mnt/c/... inside WSL, and that Docker
Desktop must be granted access to any external drive holding your photos.
EOF
}

# =============================================================================
main() {
    echo "=== Picasa — container engine setup ==="
    echo

    already_have_engine && exit 0

    case "$(uname -s)" in
        Darwin) install_macos ;;
        Linux)
            # WSL is Linux, and installing Docker inside it is a valid path, but
            # Docker Desktop's WSL integration is the smoother route — say so.
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "==> This is WSL (Linux on Windows)."
                echo "    Easiest: install Docker Desktop on Windows and enable WSL"
                echo "    integration for this distro (Settings > Resources > WSL)."
                echo
                ask "Install a container engine inside WSL instead?" || exit 0
            fi
            install_linux
            ;;
        MINGW*|MSYS*|CYGWIN*) install_windows; exit 0 ;;
        *)  echo "Unrecognised system: $(uname -s)" >&2
            echo "Install Docker or Podman manually, then run ./run.sh" >&2
            exit 1 ;;
    esac

    # Re-check, so the user gets a definite answer either way.
    echo
    if already_have_engine; then
        exit 0
    fi
    echo "==> Setup finished, but no engine is responding yet."
    echo "    That is normal if you still need to start a GUI app, start a VM,"
    echo "    or log out and back in for group changes. Then run ./run.sh"
}

main "$@"
