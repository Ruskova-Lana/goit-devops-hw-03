#!/usr/bin/env bash
#
# install_dev_tools.sh
# Automatically installs Docker, Docker Compose, Python (>= 3.9) and Django.
# Every tool is checked first, so nothing gets installed twice.
# Target OS: Debian / Ubuntu (apt-based).

set -euo pipefail

MIN_PY_MAJOR=3
MIN_PY_MINOR=9

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${YELLOW}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Use sudo only when not running as root
if [[ $EUID -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
fi

check_os() {
    if ! command -v apt-get &>/dev/null; then
        error "This script supports only Debian/Ubuntu systems (apt-get not found)."
        exit 1
    fi
}

APT_UPDATED=false
apt_update_once() {
    if [[ "$APT_UPDATED" == false ]]; then
        info "Updating package lists..."
        $SUDO apt-get update -y
        APT_UPDATED=true
    fi
}

# ---------------------------------------------------------------- Docker
install_docker() {
    if command -v docker &>/dev/null; then
        success "Docker already installed: $(docker --version)"
        return
    fi

    info "Installing Docker..."
    apt_update_once
    $SUDO apt-get install -y ca-certificates curl gnupg

    . /etc/os-release
    $SUDO install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${ID}/gpg" \
        | $SUDO gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
    $SUDO chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" \
        | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null

    APT_UPDATED=false
    apt_update_once
    $SUDO apt-get install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    # Allow running docker without sudo (takes effect after re-login)
    if [[ -n "$SUDO" ]]; then
        $SUDO usermod -aG docker "$USER" || true
        info "User '$USER' added to the 'docker' group (re-login required)."
    fi

    success "Docker installed: $(docker --version)"
}

# ---------------------------------------------------------- Docker Compose
install_docker_compose() {
    if docker compose version &>/dev/null; then
        success "Docker Compose already installed: $(docker compose version)"
        return
    fi
    if command -v docker-compose &>/dev/null; then
        success "Docker Compose already installed: $(docker-compose --version)"
        return
    fi

    info "Installing Docker Compose..."
    apt_update_once
    if ! $SUDO apt-get install -y docker-compose-plugin; then
        info "docker-compose-plugin not available, falling back to docker-compose package..."
        $SUDO apt-get install -y docker-compose
    fi

    if docker compose version &>/dev/null; then
        success "Docker Compose installed: $(docker compose version)"
    else
        success "Docker Compose installed: $(docker-compose --version)"
    fi
}

# ---------------------------------------------------------------- Python
python_version_ok() {
    command -v python3 &>/dev/null || return 1
    python3 -c "import sys; sys.exit(0 if sys.version_info >= (${MIN_PY_MAJOR}, ${MIN_PY_MINOR}) else 1)"
}

install_python() {
    if python_version_ok; then
        success "Python already installed: $(python3 --version)"
    else
        info "Installing Python ${MIN_PY_MAJOR}.${MIN_PY_MINOR}+..."
        apt_update_once
        $SUDO apt-get install -y python3 python3-venv
        if ! python_version_ok; then
            error "Installed Python is older than ${MIN_PY_MAJOR}.${MIN_PY_MINOR}: $(python3 --version)"
            exit 1
        fi
        success "Python installed: $(python3 --version)"
    fi

    if python3 -m pip --version &>/dev/null; then
        success "pip already installed: $(python3 -m pip --version)"
    else
        info "Installing pip..."
        apt_update_once
        $SUDO apt-get install -y python3-pip
        success "pip installed: $(python3 -m pip --version)"
    fi
}

# ---------------------------------------------------------------- Django
install_django() {
    if python3 -c "import django" &>/dev/null; then
        success "Django already installed: $(python3 -m django --version)"
        return
    fi

    info "Installing Django via pip..."
    local pip_args=(install --user django)

    # Python 3.11+ on Debian/Ubuntu marks the system interpreter as
    # "externally managed" (PEP 668) and blocks plain pip installs.
    if ls /usr/lib/python3*/EXTERNALLY-MANAGED &>/dev/null; then
        pip_args+=(--break-system-packages)
    fi

    python3 -m pip "${pip_args[@]}"

    # Make sure ~/.local/bin (where django-admin lives) is on PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        export PATH="$HOME/.local/bin:$PATH"
        if ! grep -qs 'HOME/.local/bin' "$HOME/.bashrc"; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
        fi
    fi

    success "Django installed: $(python3 -m django --version)"
}

main() {
    check_os
    install_docker
    install_docker_compose
    install_python
    install_django

    echo
    success "All tools are installed:"
    echo "  - $(docker --version)"
    echo "  - $(docker compose version 2>/dev/null || docker-compose --version)"
    echo "  - $(python3 --version)"
    echo "  - Django $(python3 -m django --version)"
}

main "$@"
