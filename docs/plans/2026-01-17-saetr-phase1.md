# Saetr Phase 1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build Saetr as a complete, cloneable repository that anyone can use to set up their own cloud development environment on a VPS.

**Architecture:** The repo contains everything needed: Dockerfile, management scripts, config templates, and documentation. Users clone once, customize their config, and deploy.

**Tech Stack:** Hetzner Cloud CX31, Ubuntu 24.04, Docker + Sysbox, Tailscale, GPG + pass, aws-vault, mise, Claude Code

---

## Repository Structure

```
saetr/
├── README.md                    # Quick start guide
├── DESIGN.md                    # Architecture (exists)
├── Dockerfile                   # Base image definition
├── .dockerignore                # Docker build exclusions
├── scripts/
│   ├── new-project.sh
│   ├── list-projects.sh
│   ├── recreate-project.sh
│   ├── delete-project.sh
│   ├── rebuild-image.sh
│   └── setup-host.sh            # Automated host setup
├── config/
│   ├── aws-config.template      # User copies and customizes
│   └── oathtool-mfa.sh
├── dotfiles/
│   ├── zshrc
│   ├── tmux.conf
│   └── gitconfig.template
├── cron/
│   └── rebuild-saetr-image
├── docs/
│   ├── setup-guide.md           # Detailed VPS setup walkthrough
│   └── plans/
└── .gitignore
```

---

## Phase A: Core Repository Files

Create the Dockerfile and supporting configuration in this repo.

---

### Task 1: Create .gitignore and .dockerignore

**Files:**
- Modify: `saetr/.gitignore`
- Create: `saetr/.dockerignore`

**Step 1: Update .gitignore**

```gitignore
# User-specific config (contains AWS account IDs)
config/aws-config

# Logs
*.log
logs/

# Secrets (should never be committed)
*.env
.env.*
secrets/

# OS files
.DS_Store
Thumbs.db

# Editor
.vscode/
.idea/
*.swp
*.swo
```

**Step 2: Create .dockerignore**

```dockerignore
# Git
.git
.gitignore

# Documentation
docs/
*.md
!dotfiles/*.md

# Development
.vscode/
.idea/

# OS files
.DS_Store
```

**Step 3: Commit**

```bash
git add .gitignore .dockerignore
git commit -m "chore: add .gitignore and .dockerignore

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Create Dockerfile

**Files:**
- Create: `saetr/Dockerfile`

**Step 1: Create the Dockerfile**

```dockerfile
FROM ubuntu:24.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# System packages
RUN apt-get update && apt-get install -y \
    git \
    curl \
    wget \
    build-essential \
    gnupg \
    pass \
    oathtool \
    openssh-client \
    docker.io \
    docker-compose-v2 \
    zsh \
    tmux \
    jq \
    sudo \
    locales \
    direnv \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Set up locale
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Create dev user with sudo access (no password required)
RUN useradd -m -s /bin/zsh dev && \
    usermod -aG docker dev && \
    echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Install mise (runtime version manager)
RUN curl https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh

# Install aws-vault
ARG AWS_VAULT_VERSION=7.2.0
RUN wget -q -O /usr/local/bin/aws-vault \
    "https://github.com/99designs/aws-vault/releases/download/v${AWS_VAULT_VERSION}/aws-vault-linux-amd64" && \
    chmod +x /usr/local/bin/aws-vault

# Configure aws-vault to use pass backend
ENV AWS_VAULT_BACKEND=pass

# Switch to dev user for remaining setup
USER dev
WORKDIR /home/dev

# Set up mise for dev user and install runtimes
RUN /usr/local/bin/mise use -g node@lts && \
    /usr/local/bin/mise use -g python@3.12

# Install Claude Code globally
RUN eval "$(/usr/local/bin/mise activate bash)" && \
    npm install -g @anthropic-ai/claude-code

# Create necessary directories
RUN mkdir -p \
    ~/.config/aws-vault \
    ~/.config/secrets \
    ~/.aws \
    ~/.claude/plugins/marketplaces

# Copy dotfiles
COPY --chown=dev:dev dotfiles/zshrc /home/dev/.zshrc
COPY --chown=dev:dev dotfiles/tmux.conf /home/dev/.tmux.conf

# Copy AWS vault MFA script
COPY --chown=dev:dev config/oathtool-mfa.sh /home/dev/.config/aws-vault/oathtool-mfa.sh
RUN chmod +x /home/dev/.config/aws-vault/oathtool-mfa.sh

# Note: aws-config is copied at runtime from user's customized version
# Note: dotfiles/gitconfig.template should be customized by user

WORKDIR /home/dev/project

CMD ["sleep", "infinity"]
```

**Step 2: Commit**

```bash
git add Dockerfile
git commit -m "feat: add Dockerfile for Saetr dev environment

Base image includes:
- Ubuntu 24.04
- Docker + docker-compose for DinD
- mise for runtime management (Node, Python)
- aws-vault with pass backend
- Claude Code CLI
- zsh, tmux, direnv, vim

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Create Dotfiles

**Files:**
- Create: `saetr/dotfiles/zshrc`
- Create: `saetr/dotfiles/tmux.conf`
- Create: `saetr/dotfiles/gitconfig.template`

**Step 1: Create dotfiles directory**

```bash
mkdir -p dotfiles
```

**Step 2: Create zshrc**

Create `dotfiles/zshrc`:

```bash
# =============================================================================
# Saetr Development Environment - ZSH Configuration
# =============================================================================

# Mise (runtime version manager)
eval "$(mise activate zsh)"

# Direnv (per-directory environment)
eval "$(direnv hook zsh)" 2>/dev/null || true

# AWS Vault configuration
export AWS_VAULT_BACKEND=pass

# Load secrets if available (mounted from host)
if [ -f ~/.config/secrets/common.env ]; then
    set -a
    source ~/.config/secrets/common.env
    set +a
fi

# -----------------------------------------------------------------------------
# Aliases
# -----------------------------------------------------------------------------

# General
alias ll='ls -la'
alias la='ls -A'
alias l='ls -CF'

# Docker
alias d='docker'
alias dc='docker compose'
alias dcu='docker compose up -d'
alias dcd='docker compose down'
alias dcl='docker compose logs -f'
alias dps='docker ps'
alias dpsa='docker ps -a'

# Git
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git pull'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'

# -----------------------------------------------------------------------------
# Prompt
# -----------------------------------------------------------------------------

# Simple, informative prompt: user@host:path$
PROMPT='%F{cyan}%n@%m%f:%F{yellow}%~%f$ '

# -----------------------------------------------------------------------------
# History
# -----------------------------------------------------------------------------

HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory
setopt sharehistory
setopt hist_ignore_dups

# -----------------------------------------------------------------------------
# Key bindings
# -----------------------------------------------------------------------------

bindkey -e  # Emacs-style key bindings
bindkey '^[[A' up-line-or-search
bindkey '^[[B' down-line-or-search

# -----------------------------------------------------------------------------
# Docker daemon (for Sysbox containers)
# -----------------------------------------------------------------------------

# Start Docker daemon if not running (Sysbox provides this capability)
if [ -S /var/run/docker.sock ] || sudo dockerd --version &>/dev/null; then
    if ! pgrep -x dockerd > /dev/null; then
        sudo dockerd > /tmp/dockerd.log 2>&1 &
        sleep 2
    fi
fi
```

**Step 3: Create tmux.conf**

Create `dotfiles/tmux.conf`:

```tmux
# =============================================================================
# Saetr Development Environment - Tmux Configuration
# =============================================================================

# Use C-a as prefix (like screen)
set -g prefix C-a
unbind C-b
bind C-a send-prefix

# Start windows and panes at 1, not 0
set -g base-index 1
setw -g pane-base-index 1

# Renumber windows when one is closed
set -g renumber-windows on

# Mouse support
set -g mouse on

# 256 colors
set -g default-terminal "screen-256color"

# Increase scrollback buffer
set -g history-limit 50000

# Faster key repetition
set -s escape-time 0

# -----------------------------------------------------------------------------
# Key bindings
# -----------------------------------------------------------------------------

# Split panes with | and -
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"

# Navigate panes with vim keys
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

# Reload config
bind r source-file ~/.tmux.conf \; display "Config reloaded!"

# -----------------------------------------------------------------------------
# Status bar
# -----------------------------------------------------------------------------

set -g status-style 'bg=colour235 fg=colour255'
set -g status-left '[#S] '
set -g status-right '%Y-%m-%d %H:%M'
```

**Step 4: Create gitconfig.template**

Create `dotfiles/gitconfig.template`:

```ini
# =============================================================================
# Saetr Development Environment - Git Configuration Template
# =============================================================================
# Copy this file to ~/.gitconfig inside your container and customize:
#   cp /path/to/saetr/dotfiles/gitconfig.template ~/.gitconfig
# =============================================================================

[user]
    # TODO: Set your name and email
    name = Your Name
    email = your.email@example.com

[init]
    defaultBranch = main

[pull]
    rebase = true

[push]
    autoSetupRemote = true

[core]
    editor = vim
    autocrlf = input

[alias]
    st = status
    co = checkout
    br = branch
    ci = commit
    lg = log --oneline --graph --decorate

[color]
    ui = auto
```

**Step 5: Commit**

```bash
git add dotfiles/
git commit -m "feat: add dotfiles for container environment

- zshrc: mise, direnv, aws-vault, aliases, Docker daemon auto-start
- tmux.conf: C-a prefix, mouse support, vim navigation
- gitconfig.template: user customizes with their details

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Create Config Files

**Files:**
- Create: `saetr/config/oathtool-mfa.sh`
- Create: `saetr/config/aws-config.template`

**Step 1: Create config directory**

```bash
mkdir -p config
```

**Step 2: Create MFA script**

Create `config/oathtool-mfa.sh`:

```bash
#!/bin/bash
# =============================================================================
# Saetr - TOTP MFA Script for aws-vault
# =============================================================================
# Generates TOTP codes from secrets stored in pass.
# Used by aws-vault's mfa_process configuration.
# =============================================================================

set -euo pipefail

PROFILE="${1:-dev}"
SECRET_PATH="aws/${PROFILE}-totp"

# Check if secret exists
if ! pass show "$SECRET_PATH" &>/dev/null; then
    echo "Error: TOTP secret not found at '$SECRET_PATH'" >&2
    echo "Run: pass insert $SECRET_PATH" >&2
    exit 1
fi

# Generate TOTP code
oathtool --totp --base32 "$(pass show "$SECRET_PATH")"
```

**Step 3: Create AWS config template**

Create `config/aws-config.template`:

```ini
# =============================================================================
# Saetr - AWS Configuration Template
# =============================================================================
# 1. Copy this file: cp config/aws-config.template config/aws-config
# 2. Replace YOUR_ACCOUNT_ID with your AWS account ID
# 3. Replace YOUR_IAM_USER with your IAM username
# 4. The config/aws-config file is gitignored (contains your account info)
# =============================================================================

[profile dev]
region = us-east-2
mfa_serial = arn:aws:iam::YOUR_ACCOUNT_ID:mfa/YOUR_IAM_USER
mfa_process = /home/dev/.config/aws-vault/oathtool-mfa.sh dev

# Uncomment if you need credential_process for tools that don't support aws-vault
# credential_process = /usr/local/bin/aws-vault exec dev --json
```

**Step 4: Commit**

```bash
git add config/
git commit -m "feat: add AWS and MFA configuration templates

- oathtool-mfa.sh: generates TOTP from pass-stored secrets
- aws-config.template: user customizes with their AWS account

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Create Management Scripts

**Files:**
- Create: `saetr/scripts/new-project.sh`
- Create: `saetr/scripts/list-projects.sh`
- Create: `saetr/scripts/recreate-project.sh`
- Create: `saetr/scripts/delete-project.sh`
- Create: `saetr/scripts/rebuild-image.sh`

**Step 1: Create scripts directory**

```bash
mkdir -p scripts
```

**Step 2: Create new-project.sh**

Create `scripts/new-project.sh`:

```bash
#!/bin/bash
# =============================================================================
# Saetr - Create or attach to a project container
# =============================================================================
set -e

PROJECT_NAME="$1"
SAETR_DIR="${SAETR_DIR:-$HOME/saetr}"
REGISTRY_FILE="$HOME/.saetr/port-registry.json"
IMAGE_NAME="${SAETR_IMAGE:-saetr-dev-image:latest}"

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------

if [ -z "$PROJECT_NAME" ]; then
    echo "Usage: $(basename "$0") <project-name>"
    echo ""
    echo "Creates a new isolated project container or attaches to existing one."
    echo ""
    echo "Environment variables:"
    echo "  SAETR_DIR    Path to saetr repo (default: ~/saetr)"
    echo "  SAETR_IMAGE  Docker image to use (default: saetr-dev-image:latest)"
    exit 1
fi

# Validate project name (alphanumeric and hyphens only)
if [[ ! "$PROJECT_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]]; then
    echo "Error: Project name must be alphanumeric (hyphens allowed, cannot start with hyphen)"
    exit 1
fi

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

mkdir -p "$(dirname "$REGISTRY_FILE")"

if [ ! -f "$REGISTRY_FILE" ]; then
    echo '{}' > "$REGISTRY_FILE"
fi

# -----------------------------------------------------------------------------
# Check for existing container
# -----------------------------------------------------------------------------

if docker ps -a --format '{{.Names}}' | grep -q "^${PROJECT_NAME}$"; then
    echo "Container '$PROJECT_NAME' already exists"
    PORT_BASE=$(jq -r --arg name "$PROJECT_NAME" '.[$name] // empty' "$REGISTRY_FILE")

    if [ -n "$PORT_BASE" ]; then
        echo "Ports: ${PORT_BASE}-$((PORT_BASE+9))"
    fi

    docker start "$PROJECT_NAME" 2>/dev/null || true
    echo "Attaching..."
    docker exec -it "$PROJECT_NAME" zsh
    exit 0
fi

# -----------------------------------------------------------------------------
# Find next available port
# -----------------------------------------------------------------------------

USED_PORTS=$(jq -r 'values[]' "$REGISTRY_FILE" 2>/dev/null | sort -n)
PORT_BASE=3100

for used in $USED_PORTS; do
    if [ "$PORT_BASE" -eq "$used" ]; then
        PORT_BASE=$((PORT_BASE + 100))
    fi
done

# -----------------------------------------------------------------------------
# Register port assignment
# -----------------------------------------------------------------------------

jq --arg name "$PROJECT_NAME" --argjson port "$PORT_BASE" \
    '. + {($name): $port}' "$REGISTRY_FILE" > "${REGISTRY_FILE}.tmp" \
    && mv "${REGISTRY_FILE}.tmp" "$REGISTRY_FILE"

# -----------------------------------------------------------------------------
# Create container
# -----------------------------------------------------------------------------

echo "Creating project: $PROJECT_NAME"
echo "  Ports: ${PORT_BASE}-$((PORT_BASE+9))"
echo "  Image: $IMAGE_NAME"

# Check if user has customized aws-config
AWS_CONFIG_MOUNT=""
if [ -f "$SAETR_DIR/config/aws-config" ]; then
    AWS_CONFIG_MOUNT="-v $SAETR_DIR/config/aws-config:/home/dev/.aws/config:ro"
fi

docker run -d \
    --runtime=sysbox-runc \
    --name "$PROJECT_NAME" \
    --hostname "$PROJECT_NAME" \
    -p "${PORT_BASE}:3000" \
    -p "$((PORT_BASE+1)):8000" \
    -p "$((PORT_BASE+2)):5173" \
    -p "$((PORT_BASE+3)):5432" \
    -p "$((PORT_BASE+4)):6379" \
    -p "$((PORT_BASE+5)):27017" \
    -v "$HOME/.gnupg:/home/dev/.gnupg" \
    -v "$HOME/.password-store:/home/dev/.password-store" \
    -v "$HOME/.config/secrets:/home/dev/.config/secrets:ro" \
    $AWS_CONFIG_MOUNT \
    -v "${PROJECT_NAME}-data:/home/dev/project" \
    "$IMAGE_NAME" \
    sleep infinity

echo "Container created. Attaching..."
docker exec -it "$PROJECT_NAME" zsh
```

**Step 3: Create list-projects.sh**

Create `scripts/list-projects.sh`:

```bash
#!/bin/bash
# =============================================================================
# Saetr - List all project containers
# =============================================================================

REGISTRY_FILE="$HOME/.saetr/port-registry.json"

if [ ! -f "$REGISTRY_FILE" ] || [ "$(cat "$REGISTRY_FILE")" = "{}" ]; then
    echo "No projects found."
    echo ""
    echo "Create one with: new-project.sh <project-name>"
    exit 0
fi

printf "%-20s %-12s %s\n" "PROJECT" "PORTS" "STATUS"
printf "%-20s %-12s %s\n" "-------" "-----" "------"

jq -r 'to_entries[] | "\(.key)|\(.value)"' "$REGISTRY_FILE" | sort | while IFS='|' read -r name port; do
    # Get container status
    status=$(docker ps --filter "name=^${name}$" --format "{{.Status}}" 2>/dev/null)

    if [ -z "$status" ]; then
        exists=$(docker ps -a --filter "name=^${name}$" --format "{{.Names}}" 2>/dev/null)
        if [ -n "$exists" ]; then
            status="stopped"
        else
            status="no container"
        fi
    fi

    printf "%-20s %-12s %s\n" "$name" "${port}-$((port+9))" "$status"
done
```

**Step 4: Create recreate-project.sh**

Create `scripts/recreate-project.sh`:

```bash
#!/bin/bash
# =============================================================================
# Saetr - Recreate a project container from latest image
# =============================================================================
set -e

PROJECT_NAME="$1"
SAETR_DIR="${SAETR_DIR:-$HOME/saetr}"
REGISTRY_FILE="$HOME/.saetr/port-registry.json"
IMAGE_NAME="${SAETR_IMAGE:-saetr-dev-image:latest}"

if [ -z "$PROJECT_NAME" ]; then
    echo "Usage: $(basename "$0") <project-name>"
    echo ""
    echo "Recreates container from latest image. Project data volume is preserved."
    echo "Inner Docker state (images, containers, db data) will be lost."
    exit 1
fi

PORT_BASE=$(jq -r --arg name "$PROJECT_NAME" '.[$name] // empty' "$REGISTRY_FILE")

if [ -z "$PORT_BASE" ]; then
    echo "Error: Project '$PROJECT_NAME' not found in registry."
    echo "Use new-project.sh to create a new project."
    exit 1
fi

echo "Recreating project: $PROJECT_NAME"
echo "  Ports: ${PORT_BASE}-$((PORT_BASE+9))"
echo ""
echo "WARNING: Inner Docker state (images, db data) will be lost."
echo "         Project files in /home/dev/project will be preserved."
echo ""
read -p "Continue? [y/N] " confirm

if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    echo "Cancelled."
    exit 0
fi

echo "Stopping and removing old container..."
docker stop "$PROJECT_NAME" 2>/dev/null || true
docker rm "$PROJECT_NAME" 2>/dev/null || true

echo "Creating new container from $IMAGE_NAME..."

AWS_CONFIG_MOUNT=""
if [ -f "$SAETR_DIR/config/aws-config" ]; then
    AWS_CONFIG_MOUNT="-v $SAETR_DIR/config/aws-config:/home/dev/.aws/config:ro"
fi

docker run -d \
    --runtime=sysbox-runc \
    --name "$PROJECT_NAME" \
    --hostname "$PROJECT_NAME" \
    -p "${PORT_BASE}:3000" \
    -p "$((PORT_BASE+1)):8000" \
    -p "$((PORT_BASE+2)):5173" \
    -p "$((PORT_BASE+3)):5432" \
    -p "$((PORT_BASE+4)):6379" \
    -p "$((PORT_BASE+5)):27017" \
    -v "$HOME/.gnupg:/home/dev/.gnupg" \
    -v "$HOME/.password-store:/home/dev/.password-store" \
    -v "$HOME/.config/secrets:/home/dev/.config/secrets:ro" \
    $AWS_CONFIG_MOUNT \
    -v "${PROJECT_NAME}-data:/home/dev/project" \
    "$IMAGE_NAME" \
    sleep infinity

echo "Container recreated. Attaching..."
docker exec -it "$PROJECT_NAME" zsh
```

**Step 5: Create delete-project.sh**

Create `scripts/delete-project.sh`:

```bash
#!/bin/bash
# =============================================================================
# Saetr - Delete a project container
# =============================================================================
set -e

PROJECT_NAME="$1"
REGISTRY_FILE="$HOME/.saetr/port-registry.json"

if [ -z "$PROJECT_NAME" ]; then
    echo "Usage: $(basename "$0") <project-name>"
    echo ""
    echo "Removes project container and registry entry."
    echo "Optionally deletes the data volume."
    exit 1
fi

if [ ! -f "$REGISTRY_FILE" ]; then
    echo "Error: No projects registered."
    exit 1
fi

PORT_BASE=$(jq -r --arg name "$PROJECT_NAME" '.[$name] // empty' "$REGISTRY_FILE")

if [ -z "$PORT_BASE" ]; then
    echo "Error: Project '$PROJECT_NAME' not found in registry."
    exit 1
fi

echo "Project: $PROJECT_NAME"
echo "Ports: ${PORT_BASE}-$((PORT_BASE+9))"
echo ""
echo "This will delete the container and registry entry."
read -p "Also delete the data volume (all project files)? [y/N] " delete_volume

echo ""
echo "Stopping and removing container..."
docker stop "$PROJECT_NAME" 2>/dev/null || true
docker rm "$PROJECT_NAME" 2>/dev/null || true

echo "Removing from registry..."
jq --arg name "$PROJECT_NAME" 'del(.[$name])' "$REGISTRY_FILE" > "${REGISTRY_FILE}.tmp" \
    && mv "${REGISTRY_FILE}.tmp" "$REGISTRY_FILE"

if [ "$delete_volume" = "y" ] || [ "$delete_volume" = "Y" ]; then
    echo "Deleting data volume..."
    docker volume rm "${PROJECT_NAME}-data" 2>/dev/null || true
    echo "Done. Project '$PROJECT_NAME' and data volume deleted."
else
    echo "Done. Project '$PROJECT_NAME' deleted."
    echo "Data volume '${PROJECT_NAME}-data' preserved (can be reused)."
fi
```

**Step 6: Create rebuild-image.sh**

Create `scripts/rebuild-image.sh`:

```bash
#!/bin/bash
# =============================================================================
# Saetr - Rebuild the development image
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAETR_DIR="$(dirname "$SCRIPT_DIR")"
IMAGE_NAME="${SAETR_IMAGE:-saetr-dev-image:latest}"
LOG_FILE="${SAETR_LOG:-/dev/stdout}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

cd "$SAETR_DIR"

log "Starting Saetr image rebuild..."

# Pull latest changes if this is a git repo
if [ -d .git ]; then
    log "Pulling latest changes..."
    git pull || log "Warning: git pull failed, continuing with local files"
fi

# Build the image
log "Building image: $IMAGE_NAME"
docker build -t "$IMAGE_NAME" .

# Prune old images
log "Pruning dangling images..."
docker image prune -f

log "Rebuild complete."
log "New containers will use the updated image."
log "Existing containers unchanged - use recreate-project.sh to update."
```

**Step 7: Make scripts executable and commit**

```bash
chmod +x scripts/*.sh
git add scripts/
git commit -m "feat: add project management scripts

- new-project.sh: create/attach with auto-port assignment
- list-projects.sh: show all projects with status
- recreate-project.sh: refresh from latest image
- delete-project.sh: remove with optional volume cleanup
- rebuild-image.sh: rebuild image (for cron)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: Create Host Setup Script

**Files:**
- Create: `saetr/scripts/setup-host.sh`

**Step 1: Create automated setup script**

Create `scripts/setup-host.sh`:

```bash
#!/bin/bash
# =============================================================================
# Saetr - Automated Host Setup Script
# =============================================================================
# This script installs all dependencies on a fresh Ubuntu 24.04 VPS.
# Run as a user with sudo privileges (not root).
#
# Usage: ./scripts/setup-host.sh
# =============================================================================
set -e

echo "=============================================="
echo "Saetr Host Setup"
echo "=============================================="
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo "Error: Don't run this script as root."
    echo "Run as a regular user with sudo privileges."
    exit 1
fi

# Check Ubuntu version
if ! grep -q "24.04" /etc/os-release 2>/dev/null; then
    echo "Warning: This script is designed for Ubuntu 24.04"
    read -p "Continue anyway? [y/N] " confirm
    if [ "$confirm" != "y" ]; then
        exit 1
    fi
fi

echo "This script will install:"
echo "  - Docker CE"
echo "  - Sysbox (for Docker-in-Docker)"
echo "  - Tailscale"
echo "  - 1Password CLI"
echo "  - jq, oathtool, and other utilities"
echo ""
read -p "Continue? [y/N] " confirm
if [ "$confirm" != "y" ]; then
    exit 0
fi

# -----------------------------------------------------------------------------
echo ""
echo "[1/7] Updating system packages..."
# -----------------------------------------------------------------------------
sudo apt update
sudo apt upgrade -y

# -----------------------------------------------------------------------------
echo ""
echo "[2/7] Installing Docker..."
# -----------------------------------------------------------------------------
if command -v docker &>/dev/null; then
    echo "Docker already installed: $(docker --version)"
else
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    echo "Docker installed. You'll need to log out and back in for group changes."
fi

# -----------------------------------------------------------------------------
echo ""
echo "[3/7] Installing Sysbox..."
# -----------------------------------------------------------------------------
if command -v sysbox-runc &>/dev/null; then
    echo "Sysbox already installed"
else
    SYSBOX_VERSION="0.6.4"
    wget -q "https://downloads.nestybox.com/sysbox/releases/v${SYSBOX_VERSION}/sysbox-ce_${SYSBOX_VERSION}-0.linux_amd64.deb"
    sudo dpkg -i "sysbox-ce_${SYSBOX_VERSION}-0.linux_amd64.deb" || sudo apt-get install -f -y
    rm "sysbox-ce_${SYSBOX_VERSION}-0.linux_amd64.deb"
    echo "Sysbox installed"
fi

# -----------------------------------------------------------------------------
echo ""
echo "[4/7] Installing Tailscale..."
# -----------------------------------------------------------------------------
if command -v tailscale &>/dev/null; then
    echo "Tailscale already installed"
else
    curl -fsSL https://tailscale.com/install.sh | sh
    echo "Tailscale installed"
fi

# -----------------------------------------------------------------------------
echo ""
echo "[5/7] Installing 1Password CLI..."
# -----------------------------------------------------------------------------
if command -v op &>/dev/null; then
    echo "1Password CLI already installed: $(op --version)"
else
    curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
        sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main" | \
        sudo tee /etc/apt/sources.list.d/1password.list
    sudo apt update
    sudo apt install -y 1password-cli
    echo "1Password CLI installed"
fi

# -----------------------------------------------------------------------------
echo ""
echo "[6/7] Installing utilities..."
# -----------------------------------------------------------------------------
sudo apt install -y jq oathtool vim htop

# -----------------------------------------------------------------------------
echo ""
echo "[7/7] Installing aws-vault..."
# -----------------------------------------------------------------------------
if command -v aws-vault &>/dev/null; then
    echo "aws-vault already installed"
else
    AWS_VAULT_VERSION="7.2.0"
    sudo wget -q -O /usr/local/bin/aws-vault \
        "https://github.com/99designs/aws-vault/releases/download/v${AWS_VAULT_VERSION}/aws-vault-linux-amd64"
    sudo chmod +x /usr/local/bin/aws-vault
    echo "aws-vault installed"
fi

# Add aws-vault backend to bashrc if not present
if ! grep -q "AWS_VAULT_BACKEND" ~/.bashrc; then
    echo 'export AWS_VAULT_BACKEND=pass' >> ~/.bashrc
fi

# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "Host setup complete!"
echo "=============================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Log out and back in (for Docker group)"
echo "   exit"
echo "   ssh $USER@<this-host>"
echo ""
echo "2. Start Tailscale:"
echo "   sudo tailscale up"
echo ""
echo "3. Follow the credential setup in docs/setup-guide.md:"
echo "   - Generate GPG key"
echo "   - Initialize pass"
echo "   - Add AWS credentials"
echo "   - Pull API tokens from 1Password"
echo ""
echo "4. Build the Saetr image:"
echo "   cd ~/saetr"
echo "   docker build -t saetr-dev-image:latest ."
echo ""
echo "5. Create your first project:"
echo "   ./scripts/new-project.sh my-project"
echo ""
```

**Step 2: Make executable and commit**

```bash
chmod +x scripts/setup-host.sh
git add scripts/setup-host.sh
git commit -m "feat: add automated host setup script

Installs all Saetr dependencies on Ubuntu 24.04:
- Docker CE
- Sysbox
- Tailscale
- 1Password CLI
- aws-vault
- Utilities (jq, oathtool, vim, htop)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: Create Cron Configuration

**Files:**
- Create: `saetr/cron/rebuild-saetr-image`

**Step 1: Create cron directory**

```bash
mkdir -p cron
```

**Step 2: Create cron file**

Create `cron/rebuild-saetr-image`:

```cron
# =============================================================================
# Saetr - Nightly image rebuild
# =============================================================================
# Install with: sudo cp cron/rebuild-saetr-image /etc/cron.d/
# Make sure to update the username if not 'jp'
# =============================================================================

# Rebuild Saetr dev image at 4am daily
0 4 * * * jp /home/jp/saetr/scripts/rebuild-image.sh >> /home/jp/logs/saetr-rebuild.log 2>&1
```

**Step 3: Commit**

```bash
git add cron/
git commit -m "feat: add cron configuration for nightly image rebuilds

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: Create Setup Guide Documentation

**Files:**
- Create: `saetr/docs/setup-guide.md`

**Step 1: Create setup guide**

Create `docs/setup-guide.md`:

```markdown
# Saetr Setup Guide

Complete walkthrough for setting up your Saetr cloud development environment.

## Prerequisites

- Hetzner Cloud account (or other VPS provider)
- Tailscale account
- 1Password account (for credential extraction)
- SSH key pair

## Step 1: Provision VPS

### Hetzner Cloud

1. Go to [Hetzner Cloud Console](https://console.hetzner.cloud/)
2. Create a new project (e.g., "saetr")
3. Add your SSH public key: Security → SSH Keys → Add SSH Key
4. Create server:
   - Location: **Ashburn, VA** (or closest to you)
   - Image: **Ubuntu 24.04**
   - Type: **CX31** (4 vCPU, 8GB RAM, 80GB disk) - ~$7/month
   - SSH Key: Select your key
   - Name: `saetr`
5. Note the public IP address

### Verify SSH Access

```bash
ssh root@<IP_ADDRESS>
# Should connect without password
exit
```

## Step 2: Create User Account

SSH in as root and create your user:

```bash
ssh root@<IP_ADDRESS>

# Create user (replace 'jp' with your username)
useradd -m -s /bin/bash jp
usermod -aG sudo jp
echo "jp ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set up SSH for new user
mkdir -p /home/jp/.ssh
cp ~/.ssh/authorized_keys /home/jp/.ssh/
chown -R jp:jp /home/jp/.ssh
chmod 700 /home/jp/.ssh
chmod 600 /home/jp/.ssh/authorized_keys

exit
```

Reconnect as your user:

```bash
ssh jp@<IP_ADDRESS>
```

## Step 3: Clone Saetr and Run Setup

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/saetr.git ~/saetr
cd ~/saetr

# Run automated setup
./scripts/setup-host.sh
```

The setup script installs Docker, Sysbox, Tailscale, 1Password CLI, and utilities.

**Important:** Log out and back in after setup for Docker group membership:

```bash
exit
ssh jp@<IP_ADDRESS>
```

## Step 4: Configure Tailscale

```bash
sudo tailscale up
```

Follow the authentication URL. Note your Tailscale hostname (e.g., `saetr.tailnet-name.ts.net`).

Verify from your laptop:
```bash
ping saetr.tailnet-name.ts.net
```

## Step 5: Set Up Credentials

### Generate GPG Key

```bash
gpg --full-generate-key
```

Choose:
- Key type: RSA and RSA (default)
- Key size: 4096
- Expiration: 0 (no expiration)
- Name: `cloud-jp` (or your identifier)
- Email: your email
- Passphrase: strong passphrase (you'll enter this once per session)

Note your key ID:
```bash
gpg --list-keys --keyid-format LONG
# Look for the line like: pub   rsa4096/ABCD1234EFGH5678
# ABCD1234EFGH5678 is your key ID
```

### Initialize pass

```bash
pass init <YOUR_GPG_KEY_ID>
```

### Add AWS Credentials

```bash
# Add your AWS access key and secret
aws-vault add dev
# Enter Access Key ID when prompted
# Enter Secret Access Key when prompted

# Add TOTP secret (get from AWS MFA setup or 1Password)
pass insert aws/dev-totp
# Paste your TOTP secret (base32 string)
```

Verify TOTP works:
```bash
oathtool --totp --base32 "$(pass show aws/dev-totp)"
# Should output a 6-digit code
```

### Pull API Tokens from 1Password

```bash
# Sign in to 1Password
eval $(op signin)

# Create secrets directory
mkdir -p ~/.config/secrets

# Extract credentials (adjust item name and vault as needed)
op item get "SecondBrain Shared Creds" --vault Shared --format json | \
    jq -r '.fields[] | select(.label != "") | "\(.label)=\(.value)"' > ~/.config/secrets/common.env
chmod 600 ~/.config/secrets/common.env

# Verify
cat ~/.config/secrets/common.env
```

## Step 6: Configure AWS

```bash
cd ~/saetr

# Copy and edit AWS config template
cp config/aws-config.template config/aws-config

# Edit with your AWS account details
nano config/aws-config
# Replace YOUR_ACCOUNT_ID and YOUR_IAM_USER
```

## Step 7: Build the Image

```bash
cd ~/saetr
docker build -t saetr-dev-image:latest .
```

This takes a few minutes on first build.

## Step 8: Create Your First Project

```bash
./scripts/new-project.sh my-first-project
```

You're now inside the container! Try:

```bash
# Check environment
whoami          # dev
node --version  # Node.js installed
claude --version # Claude Code installed

# Test AWS (will prompt for GPG passphrase first time)
aws-vault exec dev -- aws sts get-caller-identity

# Start Docker daemon (for docker-compose)
sudo dockerd &
sleep 3
docker ps
```

## Step 9: Set Up Nightly Rebuilds

```bash
# Create logs directory
mkdir -p ~/logs

# Install cron job (edit username if needed)
sudo cp ~/saetr/cron/rebuild-saetr-image /etc/cron.d/
```

## Daily Workflow

```bash
# From your laptop, SSH via Tailscale
ssh jp@saetr.tailnet-name.ts.net

# Start or attach to a project
./saetr/scripts/new-project.sh my-project

# Inside container, work as normal
cd /home/dev/project
git clone https://github.com/you/your-repo.git
cd your-repo
docker compose up -d
claude

# Access web services from laptop browser
# http://saetr.tailnet-name.ts.net:3100 (first project)
# http://saetr.tailnet-name.ts.net:3200 (second project)
```

## Troubleshooting

### Docker permission denied

Log out and back in to apply group membership:
```bash
exit
ssh jp@<host>
```

### Sysbox not working

Check Sysbox service:
```bash
sudo systemctl status sysbox
```

### GPG passphrase prompt every time

The gpg-agent should cache your passphrase. Check if it's running:
```bash
gpg-agent --daemon
```

### Can't reach services from laptop

1. Verify Tailscale is connected on both ends
2. Check container is running: `docker ps`
3. Check port mapping: `list-projects.sh`
4. Verify service is running inside container
```

**Step 2: Commit**

```bash
git add docs/setup-guide.md
git commit -m "docs: add comprehensive setup guide

Step-by-step walkthrough for:
- VPS provisioning (Hetzner)
- Automated host setup
- Tailscale configuration
- Credential management (GPG, pass, aws-vault)
- Image building
- First project creation
- Daily workflow
- Troubleshooting

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: Create README

**Files:**
- Create: `saetr/README.md`

**Step 1: Create README**

Create `README.md`:

```markdown
# Saetr

**Saetr** (Old Norse) — a remote summer mountain farm where work happens independently while the homestead remains free.

A self-hosted cloud development environment that runs on a VPS, providing isolated Docker-in-Docker containers for each project with persistent state, secure credential management, and instant spin-up.

## Features

- **Isolated project containers** — Each project runs in its own Sysbox container with full Docker-in-Docker capability
- **Persistent state** — Project files survive container recreation
- **Secure credentials** — GPG-encrypted secrets via `pass`, aws-vault for AWS, API tokens from 1Password
- **Auto-assigned ports** — No port conflicts between projects
- **Browser access** — View web UIs via Tailscale private network
- **Nightly updates** — Base image rebuilds automatically at 4am
- **Claude Code ready** — Pre-installed with runtime management via mise

## Quick Start

### 1. Provision a VPS

Create an Ubuntu 24.04 VPS (recommended: Hetzner CX31, ~$7/month).

### 2. Clone and Setup

```bash
# SSH into your VPS
ssh user@your-vps

# Clone Saetr
git clone https://github.com/YOUR_USERNAME/saetr.git ~/saetr
cd ~/saetr

# Run automated setup
./scripts/setup-host.sh

# Log out and back in for Docker group
exit && ssh user@your-vps
```

### 3. Configure Credentials

```bash
# Start Tailscale
sudo tailscale up

# Generate GPG key
gpg --full-generate-key

# Initialize pass
pass init <YOUR_GPG_KEY_ID>

# Add AWS credentials
aws-vault add dev
pass insert aws/dev-totp  # TOTP secret

# Configure AWS (edit with your account details)
cp ~/saetr/config/aws-config.template ~/saetr/config/aws-config
nano ~/saetr/config/aws-config
```

### 4. Build and Run

```bash
# Build the image
cd ~/saetr
docker build -t saetr-dev-image:latest .

# Create your first project
./scripts/new-project.sh my-project

# You're in! Start working
cd /home/dev/project
git clone https://github.com/you/your-repo.git
```

## Usage

### Project Management

```bash
# Create or attach to a project
./scripts/new-project.sh <project-name>

# List all projects
./scripts/list-projects.sh

# Recreate from latest image (preserves data)
./scripts/recreate-project.sh <project-name>

# Delete project
./scripts/delete-project.sh <project-name>
```

### Accessing Services

Each project gets a port range (3100-3109, 3200-3209, etc.):

| Port Offset | Default Service |
|-------------|-----------------|
| +0 (3100)   | Frontend (3000) |
| +1 (3101)   | Backend (8000)  |
| +2 (3102)   | Vite (5173)     |
| +3 (3103)   | PostgreSQL (5432) |
| +4 (3104)   | Redis (6379)    |
| +5 (3105)   | MongoDB (27017) |

Access from your laptop via Tailscale:
```
http://your-vps.tailnet.ts.net:3100
```

### Inside a Container

```bash
# Start Docker daemon (needed for docker-compose)
sudo dockerd &

# Your project files are in /home/dev/project
cd /home/dev/project

# AWS commands (prompts for GPG passphrase first time)
aws-vault exec dev -- aws s3 ls

# Claude Code
claude
```

## Documentation

- [Setup Guide](docs/setup-guide.md) — Detailed installation walkthrough
- [Design Document](DESIGN.md) — Architecture and decisions

## Requirements

- VPS: Ubuntu 24.04, 4+ vCPU, 8GB+ RAM (Hetzner CX31 recommended)
- Tailscale account
- 1Password account (optional, for credential extraction)
- AWS account (optional, for ECR/cloud access)

## License

MIT
```

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with quick start guide

Covers features, quick start, usage, and project management.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 10: Initialize Saetr Directory Structure

**Files:**
- Create: `saetr/.saetr/.gitkeep`

**Step 1: Create placeholder for saetr data directory**

The `.saetr` directory on the VPS stores runtime data. We include a gitkeep to show the expected structure.

```bash
mkdir -p .saetr
touch .saetr/.gitkeep
echo "# This directory stores runtime data on the VPS" > .saetr/README.md
echo "# - port-registry.json: project port assignments" >> .saetr/README.md
```

**Step 2: Commit**

```bash
git add .saetr/
git commit -m "chore: add .saetr directory placeholder

Runtime data directory for port registry and future state.

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 11: Final Repository Cleanup and Push

**Step 1: Review all files**

```bash
git status
ls -la
```

Expected structure:
```
saetr/
├── .dockerignore
├── .gitignore
├── .saetr/
│   ├── .gitkeep
│   └── README.md
├── Dockerfile
├── README.md
├── DESIGN.md
├── config/
│   ├── aws-config.template
│   └── oathtool-mfa.sh
├── cron/
│   └── rebuild-saetr-image
├── docs/
│   ├── setup-guide.md
│   └── plans/
│       └── 2026-01-17-saetr-phase1.md
├── dotfiles/
│   ├── gitconfig.template
│   ├── tmux.conf
│   └── zshrc
└── scripts/
    ├── delete-project.sh
    ├── list-projects.sh
    ├── new-project.sh
    ├── rebuild-image.sh
    ├── recreate-project.sh
    └── setup-host.sh
```

**Step 2: Push to GitHub**

```bash
git push origin main
```

---

## Phase B: VPS Deployment

Deploy and configure the VPS. These steps are performed on the actual VPS.

---

### Task 12: Provision Hetzner VPS

**Step 1: Create Hetzner account and project**

1. Go to https://console.hetzner.cloud/
2. Create account or sign in
3. Create project: "saetr"

**Step 2: Add SSH key**

1. Security → SSH Keys → Add SSH Key
2. Paste your public key

**Step 3: Create server**

- Location: Ashburn, VA
- Image: Ubuntu 24.04
- Type: CX31
- SSH Key: Select yours
- Name: saetr

**Step 4: Record IP address**

Note the public IP shown after creation.

---

### Task 13: Initial Server Access

**Step 1: SSH as root**

```bash
ssh root@<IP_ADDRESS>
```

**Step 2: Create user**

```bash
useradd -m -s /bin/bash jp
usermod -aG sudo jp
echo "jp ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

mkdir -p /home/jp/.ssh
cp ~/.ssh/authorized_keys /home/jp/.ssh/
chown -R jp:jp /home/jp/.ssh
chmod 700 /home/jp/.ssh
chmod 600 /home/jp/.ssh/authorized_keys

exit
```

**Step 3: Reconnect as user**

```bash
ssh jp@<IP_ADDRESS>
```

---

### Task 14: Clone Saetr and Run Setup

**Step 1: Clone the repository**

```bash
git clone https://github.com/YOUR_USERNAME/saetr.git ~/saetr
cd ~/saetr
```

**Step 2: Run setup script**

```bash
./scripts/setup-host.sh
```

**Step 3: Log out and back in**

```bash
exit
ssh jp@<IP_ADDRESS>
```

---

### Task 15: Configure Tailscale

**Step 1: Start Tailscale**

```bash
sudo tailscale up
```

**Step 2: Authenticate via the URL**

**Step 3: Note hostname**

```bash
tailscale status
# Record: saetr.tailnet-name.ts.net
```

**Step 4: Test from laptop**

```bash
ping saetr.tailnet-name.ts.net
```

---

### Task 16: Set Up GPG and pass

**Step 1: Generate GPG key**

```bash
gpg --full-generate-key
# RSA and RSA, 4096, no expiration
# Name: cloud-jp
# Email: your@email.com
# Strong passphrase
```

**Step 2: Note key ID**

```bash
gpg --list-keys --keyid-format LONG
```

**Step 3: Initialize pass**

```bash
pass init <KEY_ID>
```

---

### Task 17: Configure AWS Credentials

**Step 1: Add AWS credentials to vault**

```bash
aws-vault add dev
# Enter Access Key ID
# Enter Secret Access Key
```

**Step 2: Add TOTP secret**

```bash
pass insert aws/dev-totp
# Paste TOTP secret from AWS MFA setup
```

**Step 3: Verify TOTP**

```bash
oathtool --totp --base32 "$(pass show aws/dev-totp)"
```

**Step 4: Configure AWS config**

```bash
cd ~/saetr
cp config/aws-config.template config/aws-config
nano config/aws-config
# Replace YOUR_ACCOUNT_ID and YOUR_IAM_USER
```

---

### Task 18: Pull API Tokens from 1Password

**Step 1: Sign in**

```bash
eval $(op signin)
```

**Step 2: Extract credentials**

```bash
mkdir -p ~/.config/secrets
op item get "SecondBrain Shared Creds" --vault Shared --format json | \
    jq -r '.fields[] | select(.label != "") | "\(.label)=\(.value)"' > ~/.config/secrets/common.env
chmod 600 ~/.config/secrets/common.env
```

---

### Task 19: Build Saetr Image

**Step 1: Build the image**

```bash
cd ~/saetr
docker build -t saetr-dev-image:latest .
```

**Step 2: Verify**

```bash
docker images | grep saetr
```

---

### Task 20: Test End-to-End

**Step 1: Create test project**

```bash
./scripts/new-project.sh test-project
```

**Step 2: Verify inside container**

```bash
whoami                    # dev
node --version            # Node installed
claude --version          # Claude Code installed
cat ~/.config/secrets/common.env | head -1  # Secrets mounted

# Start Docker
sudo dockerd &
sleep 3
docker run hello-world    # Docker-in-Docker works

exit
```

**Step 3: Test port mapping**

Re-enter and start a web server:
```bash
./scripts/new-project.sh test-project
sudo dockerd &
sleep 3
docker run -d -p 3000:80 nginx
curl localhost:3000       # Works inside
exit
```

From laptop:
```bash
curl http://saetr.tailnet-name.ts.net:3100  # Works via Tailscale
```

**Step 4: Clean up test project**

```bash
./scripts/delete-project.sh test-project
# Enter 'y' to delete volume
```

---

### Task 21: Configure Nightly Rebuilds

**Step 1: Create logs directory**

```bash
mkdir -p ~/logs
```

**Step 2: Install cron job**

```bash
sudo cp ~/saetr/cron/rebuild-saetr-image /etc/cron.d/
```

**Step 3: Verify cron**

```bash
sudo systemctl status cron
```

---

### Task 22: Add Scripts to PATH

**Step 1: Add to PATH**

```bash
echo 'export PATH="$HOME/saetr/scripts:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

**Step 2: Verify**

```bash
which new-project.sh
```

---

## Summary

After completing all tasks, you have:

1. ✅ Complete Saetr repository with all code
2. ✅ Dockerfile for dev environment
3. ✅ Management scripts (new, list, recreate, delete)
4. ✅ Automated host setup script
5. ✅ Documentation (README, setup guide, design doc)
6. ✅ VPS running on Hetzner with all dependencies
7. ✅ Tailscale for secure access
8. ✅ Credentials configured (GPG, pass, aws-vault)
9. ✅ Nightly rebuild cron job

**For others to use Saetr:**

```bash
# Clone
git clone https://github.com/YOUR_USERNAME/saetr.git ~/saetr

# Follow setup guide
cat ~/saetr/docs/setup-guide.md
```
