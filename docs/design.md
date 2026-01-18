# Saetr

## Name

**Saetr** (Old Norse, also spelled "seter" or "stol") — a remote summer mountain farm or outpost in Scandinavian tradition.

In Viking-age Scandinavia, a saetr was a seasonal camp in the highlands where animals were sent to graze and workers would tend to them. It was self-sufficient, had everything needed to operate, and work continued there while the farmer was elsewhere at the main homestead.

This project is a saetr for development work: a remote, self-sufficient environment where work can happen independently. You set it up, send tasks to it, and check in periodically — while your local machine (the homestead) remains free.

---

## Overview

A self-hosted platform where agents do the work. Spin up a project, implement a feature, review a PR, run the tests — autonomously. Check in on agents anytime, or use it yourself as a remote dev environment.

---

## Phase 1 Requirements

### Must Have
- Run full Docker stack (db, backend, frontend, etc.) per project
- Claude Code with my plugins/skills/config
- Persistent state per project (pick up where I left off)
- Credentials for AWS (ECR pull) and API tokens
- Nightly auto-rebuild of base image (Claude Code + plugins)
- SSH access from laptop
- Browser access to container services via Tailscale
- Instant spin-up for new projects
- Each project is its own isolated container
- Auto-assigned port ranges (no conflicts between projects)

### Not Phase 1
- Phone access / web UI
- HTTPS URLs for sharing with others
- Caddy reverse proxy with custom domain

---

## Architecture

### High-Level Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│ VPS (Host)                                                          │
│                                                                     │
│  Tailscale ──────────────────────────────────► Laptop (Tailscale)   │
│                                                                     │
│  Shared from Host:                                                  │
│  ├── ~/.gnupg/              (GPG keys)            [read-write]      │
│  ├── ~/.password-store/     (aws creds, TOTP)     [read-write]      │
│  ├── ~/.config/secrets/     (API tokens)          [read-only]       │
│  ├── ~/.claude/             (auth + plugins)      [read-write]      │
│  ├── ~/.ssh/                (SSH keys)            [read-only]       │
│  └── ~/.gitconfig           (git identity)        [read-only]       │
│                                                                     │
│  Port Registry: ~/.saetr/port-registry.json                         │
│                                                                     │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐      │
│  │ project-a       │  │ project-b       │  │ project-c       │      │
│  │ ports 3100-3109 │  │ ports 3200-3209 │  │ ports 3300-3309 │      │
│  │                 │  │                 │  │                 │      │
│  │ Sysbox runtime  │  │ Sysbox runtime  │  │ Sysbox runtime  │      │
│  │ Docker-in-Docker│  │ Docker-in-Docker│  │ Docker-in-Docker│      │
│  │                 │  │                 │  │                 │      │
│  │ Volume:         │  │ Volume:         │  │ Volume:         │      │
│  │ project-a-data  │  │ project-b-data  │  │ project-c-data  │      │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘      │
│                                                                     │
│  Cron: 4am daily image rebuild                                      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

Browser access: http://<tailscale-hostname>:3100 → project-a frontend
```

### Port Mapping Flow

```
Laptop browser
     │
     ▼ http://vps.tailnet:3100
┌─────────────────────────────────────────┐
│ VPS Host                                │
│                                         │
│   :3100 ──┐                             │
│           │                             │
│   ┌───────▼─────────────────────────┐   │
│   │ project-a container             │   │
│   │   -p 3100:3000 (frontend)       │   │
│   │   -p 3101:8000 (backend)        │   │
│   │   -p 3102:5173 (vite)           │   │
│   │                                 │   │
│   │   ┌─────────────────────────┐   │   │
│   │   │ Inner Docker            │   │   │
│   │   │  frontend:3000 ─────────┼───┼──► :3100
│   │   │  backend:8000  ─────────┼───┼──► :3101
│   │   │  postgres:5432 (internal)   │   │
│   │   └─────────────────────────┘   │   │
│   └─────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

### Component Details

#### Host (VPS)

| Component | Purpose |
|-----------|---------|
| Docker + Sysbox | Container runtime with VM-like capabilities |
| Tailscale | Secure private network access from laptop |
| 1Password CLI | Initial secret extraction (one-time setup) |
| GPG + pass | Credential storage (shared across containers) |
| jq | JSON processing for port registry |
| Cron | Nightly image rebuild |

**Recommended: Hetzner Cloud CPX21** ($9.99/month)
- 3 vCPUs (AMD)
- 4GB RAM
- 80GB disk (expandable with volumes)
- Location: Ashburn, VA (closest to AWS us-east-2)

Upgrade to **CPX31** ($17.99/month, 4 vCPU, 8GB RAM) if running multiple heavy Docker stacks.

#### Base Image (rebuilt nightly)

**Baked in:**
- OS packages (git, curl, build-essential, jq, etc.)
- Language runtimes (Node, Python via mise)
- Docker + docker-compose
- Claude Code CLI
- aws-vault (configured for pass backend)
- pass + GPG + oathtool
- direnv + mise
- Dotfiles (.zshrc, .tmux.conf, .envrc)

**Mounted at runtime:**
- `~/.aws/config` — AWS profiles and MFA config (from `config/aws-config`)
- `~/.gnupg/` (GPG keys) — read-write for gpg-agent sockets and lock files
- `~/.password-store/` (credentials) — read-write for aws-vault session token caching
- `~/.config/secrets/` (API tokens) — read-only, includes GH_TOKEN, GRAPHITE_TOKEN
- `~/.claude/` (Claude Code) — read-write, subscription auth and plugins shared across containers
- `~/.ssh/` (SSH keys) — read-only, for git clone via SSH
- `~/.gitconfig` (git identity) — read-only, conditional (only if file exists)
- Project data volume

**First-run setup (manual):**
- CLI tools requiring AWS CodeArtifact auth can be installed manually: `uv pip install huginn mimir`
- Automated setup deferred to Phase 2 CLI

**Managed on host (shared across containers):**
- Claude Code plugins/skills — install on host, all containers see updates immediately

#### Per-Project Container

```bash
docker run -d \
  --runtime=sysbox-runc \
  --name <project-name> \
  --hostname <project-name> \
  -p <port-base>:3000 \
  -p <port-base+1>:8000 \
  -p <port-base+2>:5173 \
  -p <port-base+3>:5432 \
  -v ~/.gnupg:/home/dev/.gnupg \
  -v ~/.password-store:/home/dev/.password-store \
  -v ~/.config/secrets:/home/dev/.config/secrets:ro \
  -v ~/.claude:/home/dev/.claude \
  -v ~/.ssh:/home/dev/.ssh:ro \
  -v ~/.gitconfig:/home/dev/.gitconfig:ro \
  -v <project-name>-data:/home/dev/project \
  my-dev-image:latest
```

---

## Container Lifecycle

### Design Principles

Containers are **long-running** but can be **manually recreated** when you want updates.

| Scenario | What Survives | When to Use |
|----------|---------------|-------------|
| Daily work | Everything | Normal operation |
| Container restart | Project volume only | After crash or reboot |
| Container recreate | Project volume only | When you want fresh image with updates |

### What Persists vs Resets

**Persists (named volume):**
- Git repos and uncommitted work
- Project files in `/home/dev/project`

**Resets on recreate:**
- Inner Docker state (images, containers, volumes)
- Shell history, tmux sessions
- Cached dependencies (node_modules, venv, etc.)

**Acceptable trade-off:** After recreation, first `docker-compose up` re-pulls images and databases start fresh. This matches the "clean slate" workflow.

---

## Credentials & Security

### Security Principles

| Principle | Local (macOS) | Cloud (Linux) |
|-----------|---------------|---------------|
| Credentials encrypted at rest | Keychain | pass + GPG |
| Unlock once per session | Keychain unlock | GPG unlock via gpg-agent |
| Short-lived AWS tokens | aws-vault + STS | aws-vault + STS |
| MFA required | 1Password TOTP | oathtool + pass |

### GPG Agent Caching

The `~/.gnupg` directory is mounted **read-write** to allow `gpg-agent` to cache the passphrase. You enter your GPG passphrase once per container session.

**Security note:** The `saetr-vps` GPG key is scoped specifically for this cloud environment, separate from any local keys.

### Credential Flow Comparison

**Local (macOS):**
```
aws command
    │
    ▼
aws-vault exec
    │
    ▼
Reads credentials from Keychain
    │
    ▼
Calls 1Password for TOTP (mfa_process)
    │
    ▼
STS returns session token
```

**Cloud (Linux):**
```
aws command
    │
    ▼
aws-vault exec
    │
    ▼
Reads credentials from pass (GPG-encrypted)
    │
    ▼
Calls oathtool + pass for TOTP (mfa_process)
    │
    ▼
STS returns session token
```

### Credential Storage on Host

```
~/.gnupg/
├── private-keys-v1.d/    (saetr-vps private key)
├── pubring.kbx           (public keyring)
└── trustdb.gpg           (trust database)

~/.password-store/
├── aws/
│   ├── dev-access-key.gpg
│   ├── dev-secret-key.gpg
│   └── dev-totp.gpg
└── .gpg-id

~/.config/secrets/
├── common.env            (ANTHROPIC_API_KEY, etc.)
└── <other-credentials>
```

### AWS Configuration

**~/.aws/config (mounted at runtime from `config/aws-config`):**
```ini
[profile dev]
region = us-east-2
mfa_serial = arn:aws:iam::<account-id>:mfa/<user>
mfa_process = ~/.config/aws-vault/oathtool-mfa.sh dev
credential_process = /usr/local/bin/aws-vault exec dev --json
```

**~/.config/aws-vault/oathtool-mfa.sh (baked into image):**
```bash
#!/bin/bash
PROFILE="${1:-dev}"
oathtool --totp --base32 "$(pass show aws/${PROFILE}-totp)"
```

### Scoped Credentials

Create dedicated IAM user for cloud environment with limited permissions:
- `ecr:GetAuthorizationToken`
- `ecr:BatchGetImage`
- `ecr:GetDownloadUrlForLayer`
- Other specific permissions as needed

These credentials are separate from your primary AWS credentials.

---

## Claude Code Setup

### Architecture

Claude Code uses a split installation:
- **Container**: Claude Code CLI binary (baked into image)
- **Host**: `~/.claude/` directory mounted into containers (auth, plugins, settings)

This means:
- Subscription auth is configured once on host, shared by all containers
- Plugins are installed on host, immediately available everywhere
- Settings are consistent across all containers

### Host Setup

```bash
# Install Claude Code on host
curl -fsSL https://claude.ai/install.sh | bash

# Login (subscription auth)
~/.local/bin/claude login

# Install plugins (on host)
cd ~/.claude/plugins/marketplaces
git clone https://github.com/your-org/secondbrain.git
~/.local/bin/claude plugin install <plugin>@secondbrain
```

### Updates

| Update Type | Where | How |
|-------------|-------|-----|
| Claude Code CLI | Container | Rebuild image |
| Plugins | Host | `git pull` in marketplace dir |
| CLI tools (huginn, mimir) | Container | Manual install or Phase 2 CLI |

---

## Daily Workflow

### Morning (automated)

```
4:00 AM - Cron triggers image rebuild
    │
    ▼
Pull latest marketplace repos
    │
    ▼
docker build -t my-dev-image:latest .
    │
    ▼
Prune old images
```

### Workday

```
SSH into host (or use Tailscale hostname)
    │
    ▼
./new-project.sh <project-name>  (creates or attaches)
    │
    ▼
First AWS command prompts for GPG passphrase (once per container)
    │
    ▼
docker-compose up -d
    │
    ▼
Work with Claude Code
    │
    ▼
Browser: http://<tailscale-hostname>:<port> to view UI
    │
    ▼
End of day: stop at clean point, exit container
```

### Switching Projects

```
Exit current container (Ctrl+D or exit)
    │
    ▼
./new-project.sh <other-project>
    │
    ▼
docker-compose up -d (if services not running)
    │
    ▼
Continue working
```

### Updating a Long-Running Container

If a container has been running for a while and you want the latest plugins:

```
On host:
    │
    ▼
cd ~/.claude/plugins/marketplaces/secondbrain && git pull
    │
    ▼
Plugins update immediately (shared via volume mount)
```

Or for a full refresh:

```
Exit container
    │
    ▼
./recreate-project.sh <project-name>
    │
    ▼
Fresh container from latest image (port assignment preserved)
```

---

## Scripts

> **Note:** The examples below show simplified versions for documentation. See `scripts/` for the actual implementations, which include additional features like input validation, environment variable support (`SAETR_DIR`, `SAETR_IMAGE`), and checksum verification.

### new-project.sh

Creates a new project container with auto-assigned ports, or attaches to existing.

```bash
#!/bin/bash
set -e

PROJECT_NAME="$1"
REGISTRY_FILE="$HOME/.saetr/port-registry.json"

if [ -z "$PROJECT_NAME" ]; then
  echo "Usage: ./new-project.sh <project-name>"
  exit 1
fi

# Ensure registry directory exists
mkdir -p "$(dirname "$REGISTRY_FILE")"

# Initialize registry if missing
if [ ! -f "$REGISTRY_FILE" ]; then
  echo '{}' > "$REGISTRY_FILE"
fi

# Check if container already exists
if docker ps -a --format '{{.Names}}' | grep -q "^${PROJECT_NAME}$"; then
  echo "Container '$PROJECT_NAME' already exists"
  PORT_BASE=$(jq -r --arg name "$PROJECT_NAME" '.[$name] // empty' "$REGISTRY_FILE")
  echo "Ports: ${PORT_BASE}-$((PORT_BASE+9))"
  docker start "$PROJECT_NAME" 2>/dev/null || true
  docker exec -it "$PROJECT_NAME" bash
  exit 0
fi

# Find next available port base (3100, 3200, 3300, ...)
USED_PORTS=$(jq -r 'values[]' "$REGISTRY_FILE" | sort -n)
PORT_BASE=3100

for used in $USED_PORTS; do
  if [ "$PORT_BASE" -eq "$used" ]; then
    PORT_BASE=$((PORT_BASE + 100))
  fi
done

# Register the assignment
jq --arg name "$PROJECT_NAME" --argjson port "$PORT_BASE" \
  '. + {($name): $port}' "$REGISTRY_FILE" > "${REGISTRY_FILE}.tmp" \
  && mv "${REGISTRY_FILE}.tmp" "$REGISTRY_FILE"

echo "Creating project: $PROJECT_NAME (ports ${PORT_BASE}-$((PORT_BASE+9)))"

docker run -d \
  --runtime=sysbox-runc \
  --name "$PROJECT_NAME" \
  --hostname "$PROJECT_NAME" \
  -p ${PORT_BASE}:3000 \
  -p $((PORT_BASE+1)):8000 \
  -p $((PORT_BASE+2)):5173 \
  -p $((PORT_BASE+3)):5432 \
  -v ~/.gnupg:/home/dev/.gnupg \
  -v ~/.password-store:/home/dev/.password-store \
  -v ~/.config/secrets:/home/dev/.config/secrets:ro \
  -v "${PROJECT_NAME}-data:/home/dev/project" \
  my-dev-image:latest \
  sleep infinity

echo "Container created. Attaching..."
docker exec -it "$PROJECT_NAME" bash
```

### list-projects.sh

Shows all projects with their port assignments and status.

```bash
#!/bin/bash

REGISTRY_FILE="$HOME/.saetr/port-registry.json"

if [ ! -f "$REGISTRY_FILE" ]; then
  echo "No projects found."
  exit 0
fi

echo "PROJECT          PORTS       STATUS"
echo "-------          -----       ------"
jq -r 'to_entries[] | "\(.key)|\(.value)"' "$REGISTRY_FILE" | while IFS='|' read name port; do
  status=$(docker ps --filter "name=^${name}$" --format "{{.Status}}" 2>/dev/null)
  if [ -z "$status" ]; then
    # Check if container exists but is stopped
    exists=$(docker ps -a --filter "name=^${name}$" --format "{{.Names}}" 2>/dev/null)
    if [ -n "$exists" ]; then
      status="stopped"
    else
      status="no container"
    fi
  fi
  printf "%-16s %-11s %s\n" "$name" "${port}-$((port+9))" "$status"
done
```

### recreate-project.sh

Recreates a container from the latest image, preserving port assignment.

```bash
#!/bin/bash
set -e

PROJECT_NAME="$1"
REGISTRY_FILE="$HOME/.saetr/port-registry.json"

if [ -z "$PROJECT_NAME" ]; then
  echo "Usage: ./recreate-project.sh <project-name>"
  exit 1
fi

# Get existing port assignment
PORT_BASE=$(jq -r --arg name "$PROJECT_NAME" '.[$name] // empty' "$REGISTRY_FILE")

if [ -z "$PORT_BASE" ]; then
  echo "Project '$PROJECT_NAME' not found in registry."
  echo "Use ./new-project.sh to create a new project."
  exit 1
fi

echo "Recreating project: $PROJECT_NAME (ports ${PORT_BASE}-$((PORT_BASE+9)))"
echo "WARNING: Inner Docker state (images, db data) will be lost."
read -p "Continue? [y/N] " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
  echo "Cancelled."
  exit 0
fi

# Stop and remove existing container
docker stop "$PROJECT_NAME" 2>/dev/null || true
docker rm "$PROJECT_NAME" 2>/dev/null || true

# Create fresh container
docker run -d \
  --runtime=sysbox-runc \
  --name "$PROJECT_NAME" \
  --hostname "$PROJECT_NAME" \
  -p ${PORT_BASE}:3000 \
  -p $((PORT_BASE+1)):8000 \
  -p $((PORT_BASE+2)):5173 \
  -p $((PORT_BASE+3)):5432 \
  -v ~/.gnupg:/home/dev/.gnupg \
  -v ~/.password-store:/home/dev/.password-store \
  -v ~/.config/secrets:/home/dev/.config/secrets:ro \
  -v "${PROJECT_NAME}-data:/home/dev/project" \
  my-dev-image:latest \
  sleep infinity

echo "Container recreated. Attaching..."
docker exec -it "$PROJECT_NAME" bash
```

### delete-project.sh

Removes a project container and its registry entry (optionally the data volume).

```bash
#!/bin/bash
set -e

PROJECT_NAME="$1"
REGISTRY_FILE="$HOME/.saetr/port-registry.json"

if [ -z "$PROJECT_NAME" ]; then
  echo "Usage: ./delete-project.sh <project-name>"
  exit 1
fi

echo "This will delete the container and registry entry for '$PROJECT_NAME'."
read -p "Also delete the data volume? [y/N] " delete_volume

# Stop and remove container
docker stop "$PROJECT_NAME" 2>/dev/null || true
docker rm "$PROJECT_NAME" 2>/dev/null || true

# Remove from registry
jq --arg name "$PROJECT_NAME" 'del(.[$name])' "$REGISTRY_FILE" > "${REGISTRY_FILE}.tmp" \
  && mv "${REGISTRY_FILE}.tmp" "$REGISTRY_FILE"

# Optionally delete volume
if [ "$delete_volume" = "y" ] || [ "$delete_volume" = "Y" ]; then
  docker volume rm "${PROJECT_NAME}-data" 2>/dev/null || true
  echo "Project '$PROJECT_NAME' and its data volume deleted."
else
  echo "Project '$PROJECT_NAME' deleted. Data volume '${PROJECT_NAME}-data' preserved."
fi
```

### rebuild-image.sh

```bash
#!/bin/bash
set -e

cd ~/dev-image

echo "Pulling latest config..."
git pull

echo "Updating marketplace repos..."
# Pull latest for each marketplace
for dir in marketplaces/*/; do
  if [ -d "$dir/.git" ]; then
    echo "  Updating $dir..."
    git -C "$dir" pull
  fi
done

echo "Building image..."
docker build -t my-dev-image:latest .

echo "Pruning old images..."
docker image prune -f

echo "Done. New containers will use updated image."
echo "Existing containers unchanged (recreate to update)."
```

### Cron entry

```
# /etc/cron.d/rebuild-dev-image
0 4 * * * <username> /home/<username>/saetr/scripts/rebuild-image.sh >> /home/<username>/logs/saetr-rebuild.log 2>&1
```

---

## One-Time Host Setup

### 1. Install Docker + Sysbox

```bash
# Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Sysbox
wget https://downloads.nestybox.com/sysbox/releases/v0.6.4/sysbox-ce_0.6.4-0.linux_amd64.deb
sudo dpkg -i sysbox-ce_0.6.4-0.linux_amd64.deb
```

### 2. Install Tailscale

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

Note your Tailscale hostname (e.g., `my-vps.tailnet-name.ts.net`).

### 3. Install 1Password CLI

```bash
curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
  sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main" | \
  sudo tee /etc/apt/sources.list.d/1password.list
sudo apt update && sudo apt install 1password-cli
```

### 4. Install jq

```bash
sudo apt install jq
```

### 5. Generate saetr-vps GPG key

```bash
gpg --full-generate-key
# Choose: RSA and RSA, 4096 bits, no expiration
# Name: saetr-vps
# Email: <your-email>
```

### 6. Initialize pass

```bash
pass init <gpg-key-id>
```

### 7. Add AWS credentials to pass

```bash
# Add access key
aws-vault add dev
# When prompted, enter your scoped access key and secret

# Add TOTP secret
pass insert aws/dev-totp
# Paste the TOTP secret (base32 string from AWS MFA setup)
```

### 8. Pull API tokens from 1Password

```bash
op signin
op item get "SecondBrain Shared Creds" --vault Shared --format json | \
  jq -r '.fields[] | select(.label != "") | "\(.label)=\(.value)"' > ~/.config/secrets/common.env
chmod 600 ~/.config/secrets/common.env
```

### 9. Initialize Saetr directory

```bash
mkdir -p ~/.saetr
echo '{}' > ~/.saetr/port-registry.json
```

### 10. Clone dev-image repo and build

```bash
git clone <your-dev-image-repo> ~/dev-image
cd ~/dev-image
docker build -t my-dev-image:latest .
```

### 11. Install scripts

```bash
mkdir -p ~/scripts ~/logs
cp ~/dev-image/scripts/*.sh ~/scripts/
chmod +x ~/scripts/*.sh
```

### 12. Set up cron

```bash
sudo cp ~/dev-image/rebuild-dev-image.cron /etc/cron.d/rebuild-dev-image
```

---

## Dockerfile Outline

> **Note:** See `Dockerfile` for the actual implementation. This outline shows the key architectural decisions.

```dockerfile
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# System packages
RUN apt-get update && apt-get install -y \
    git curl wget unzip build-essential \
    gnupg pass oathtool \
    openssh-client \
    docker.io docker-compose-v2 \
    zsh tmux jq sudo locales direnv vim \
    && rm -rf /var/lib/apt/lists/*

# AWS CLI v2 (official installer)
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install && \
    rm -rf /tmp/awscliv2.zip /tmp/aws

# Locale setup
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Create dev user (UID 1000 for bind mount compatibility)
# Ubuntu 24.04 has a default 'ubuntu' user at UID 1000, remove it first
RUN userdel -r ubuntu 2>/dev/null || true && \
    useradd -m -s /bin/zsh -u 1000 dev && \
    usermod -aG docker dev && \
    echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Install mise (runtime version manager) - download then run pattern
RUN curl -fsSL https://mise.run -o /tmp/mise-install.sh && \
    chmod +x /tmp/mise-install.sh && \
    MISE_INSTALL_PATH=/usr/local/bin/mise /tmp/mise-install.sh && \
    rm /tmp/mise-install.sh

# Install aws-vault with checksum verification
ARG AWS_VAULT_VERSION=7.2.0
ARG AWS_VAULT_SHA256=b92bcfc4a78aa8c547ae5920d196943268529c5dbc9c5aca80b797a18a5d0693
RUN wget -q -O /tmp/aws-vault \
    "https://github.com/99designs/aws-vault/releases/download/v${AWS_VAULT_VERSION}/aws-vault-linux-amd64" && \
    echo "${AWS_VAULT_SHA256}  /tmp/aws-vault" | sha256sum -c - && \
    mv /tmp/aws-vault /usr/local/bin/aws-vault && \
    chmod +x /usr/local/bin/aws-vault

ENV AWS_VAULT_BACKEND=pass

# Install uv (Python package manager) and just (command runner)
RUN curl -LsSf https://astral.sh/uv/install.sh | CARGO_HOME=/usr/local UV_INSTALL_DIR=/usr/local/bin sh
RUN curl -fsSL https://just.systems/install.sh | sh -s -- --to /usr/local/bin

# Install GitHub CLI (gh)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y gh && rm -rf /var/lib/apt/lists/*

# Switch to dev user
USER dev
WORKDIR /home/dev

# Install runtimes via mise
RUN /usr/local/bin/mise use -g node@lts && \
    /usr/local/bin/mise use -g python@3.12

# Install Graphite CLI (gt) for stacked branches
RUN /bin/bash -c 'eval "$(/usr/local/bin/mise activate bash)" && npm install -g @withgraphite/graphite-cli'

# Install Claude Code (native installer)
RUN curl -fsSL https://claude.ai/install.sh | bash

# Create necessary directories
RUN mkdir -p ~/.config/aws-vault ~/.config/secrets ~/.aws ~/.claude/plugins/marketplaces

# Copy dotfiles and config
COPY --chown=dev:dev dotfiles/zshrc /home/dev/.zshrc
COPY --chown=dev:dev dotfiles/tmux.conf /home/dev/.tmux.conf
COPY --chown=dev:dev config/oathtool-mfa.sh /home/dev/.config/aws-vault/oathtool-mfa.sh
RUN chmod +x /home/dev/.config/aws-vault/oathtool-mfa.sh

# Note: aws-config is mounted at runtime from user's customized version

WORKDIR /home/dev/project
CMD ["sleep", "infinity"]
```

**Key implementation details:**

- **Checksum verification** for aws-vault prevents supply chain attacks
- **UID 1000** for dev user ensures bind mount permissions work correctly
- **Download-then-run pattern** for install scripts (vs `curl | sh`) allows inspection
- **AWS CLI v2** included for direct AWS operations alongside aws-vault
- **uv and just** provide modern Python packaging and task running
- **gh and gt** enable GitHub PR workflows and Graphite stacked branches

---

## Project Scale

- **Work projects:** ~5 currently, scaling to ~10
- **Side projects:** ~5 for experimenting
- **Total:** ~15 isolated project containers
- **Concurrent active:** 1-2 (with Docker stack running)
- **Rest:** Idle (container exists, no services running)

---

## Cost Estimate

**Hetzner Cloud (Recommended):**

| Plan | Monthly Cost | Specs |
|------|--------------|-------|
| CPX11 | $4.99 | 2 vCPU, 2GB RAM, 40GB disk |
| **CPX21** | **$9.99** | **3 vCPU, 4GB RAM, 80GB disk** |
| CPX31 | $17.99 | 4 vCPU, 8GB RAM, 160GB disk |
| CPX41 | $33.49 | 8 vCPU, 16GB RAM, 240GB disk |

**Recommendation:** Start with CPX21 ($9.99/month). Upgrade to CPX31 if memory becomes a bottleneck with multiple active projects.

---

## Future Phases

### Phase 2: CLI

A unified `saetr` CLI tool with flat command structure. Explicit names as primary commands, short aliases for convenience.

**Host-level commands (no project arg):**

| Primary | Alias | Description |
|---------|-------|-------------|
| `saetr list` | `ls` | List all projects with status and ports |
| `saetr build` | | Rebuild Docker image |
| `saetr status` | | Overview: disk, containers, image age |
| `saetr prune` | | Clean up images and volumes |
| `saetr update` | | Pull latest saetr repo |

**Project-level commands (require `<project>` arg):**

| Primary | Alias | Description |
|---------|-------|-------------|
| `saetr create <project>` | | Create container (don't attach) |
| `saetr attach <project>` | | Attach to running container |
| `saetr new <project>` | | Create if needed + attach |
| `saetr delete <project>` | `rm` | Delete container (prompt for volume) |
| `saetr recreate <project>` | | Recreate from latest image |
| `saetr start <project>` | | Start stopped container |
| `saetr stop <project>` | | Stop container |
| `saetr info <project>` | | Detailed project info |
| `saetr logs <project>` | | View container logs |
| `saetr exec <project> <cmd>` | | Run command without attaching |
| `saetr ports <project>` | | Show port mappings |

**Behavior:**
- `create` - creates container, leaves it running detached
- `attach` - attaches to existing container (fails if doesn't exist)
- `new` - `create` if needed, then `attach` (convenience combo)

**Security improvements to consider:**
- `saetr tools-sync` — Automated CLI tool installation (replaces manual setup)
- Systemd-based dockerd management (alternative to sudo in zshrc)

### Phase 3: Headless Automation

**Ephemeral task containers:**

Temporary containers spun up for a specific task, destroyed on completion. Multiple tasks can run on the same repo concurrently.

Example triggers:
- `saetr task <repo> --ticket LINEAR-123 "implement the feature"` → implement ticket
- `saetr task <repo> --pr 456 "review and test"` → review PR, run tests, approve or request changes
- `saetr task <repo> "research how auth works and report back"` → ad-hoc investigation

Lifecycle:
1. Creates temporary container (e.g., `spacewalker-LINEAR-123`, `spacewalker-pr-456`)
2. Does the work headlessly
3. Reports back, waits for approval if needed
4. Destroys on completion

**Infrastructure:**
- Non-interactive operation (stored GPG passphrase for headless triggering)
- Task queue for "work on ticket X"
- Notifications when blocked or done
- PR automation
- Slack/webhook triggers
- Resource monitoring/alerts

**Security improvements required:**
- Per-project credential isolation — Autonomous agents running less-supervised code should not share credentials with other projects. Options:
  - Credential proxy service on host (containers request tokens, don't mount secrets directly)
  - Per-project GPG keys and pass stores
  - Scoped AWS IAM roles per project
- Audit logging — Track what credentials each container accesses
- Resource limits — Prevent runaway containers from affecting others

### Phase 4: HTTPS for Sharing
- Caddy with wildcard cert
- `project-a.dev.yourdomain.com` routing
- For sharing previews with others (stakeholders, demos)

---

## Ideas (not yet scheduled)

- **Nightly image rebuilds** — Auto-rebuild at 4am to keep tools current. Trade-off: self-maintaining vs. risk of bad update breaking things. More valuable for Phase 3 headless automation where agents run unattended.
- SSH from phone (Termius/Blink) via Tailscale
- Multiple VPS support (spin up Saetr on different providers)
- Project templates (pre-configured stacks)
- Backup/restore for project volumes

### Security Roadmap

**Current state (Phase 1):** Credentials shared across all containers. Acceptable for single-user personal dev environment where all code is trusted.

**Phase 2 considerations:**
- Restrict sudoers further (currently only `/usr/bin/dockerd` is passwordless)
- Consider systemd for dockerd lifecycle management
- Automated tool installation via CLI

**Phase 3 requirements:**
- Per-project credential scoping is mandatory for autonomous agents
- Audit logging for credential access
- Resource isolation and limits
- Consider read-only credential mounts where possible

---

## Resolved Decisions

1. **Backup strategy** — Not needed for Phase 1. Code is always synced to GitHub. Credentials can be recreated via one-time setup (~30 min).

2. **Monitoring** — Not Phase 1. Future: basic host reachability check via UptimeRobot or similar.

3. **VPS provider** — Hetzner Cloud CX31, Ashburn datacenter.

4. **First-run setup** — CLI tools (huginn, mimir) can be installed manually. Automated setup deferred to Phase 2 CLI.

5. **AWS profiles** — Dev only. No prod access needed from cloud environment.

---

## Appendix: Local vs Cloud Comparison

| Aspect | Local (macOS) | Cloud (Linux) |
|--------|---------------|---------------|
| Credential storage | Keychain | pass + GPG |
| MFA | 1Password TOTP | oathtool + pass |
| Environment loading | direnv + mise | direnv + mise |
| Docker | Docker Desktop | Docker + Sysbox |
| Project isolation | Directories | Containers |
| Always on | No | Yes |
| Accessible anywhere | No | Yes (Tailscale) |
| Browser access to services | localhost | Tailscale hostname + port |

---

## Appendix: Implementation Deviations from Local Setup

The cloud environment maintains the same security architecture and workflow as the local macOS setup, but uses different tools where platform-specific solutions are required.

### Credential Storage

| | Local | Cloud | Why |
|---|---|---|---|
| Backend | macOS Keychain | pass + GPG | Keychain is macOS-only. pass is the standard Linux equivalent with GPG encryption at rest. |
| Unlock mechanism | macOS login / Touch ID | GPG passphrase (cached by gpg-agent) | No biometrics available in headless Linux. gpg-agent caches unlock for configurable duration. |
| aws-vault backend | `keychain` | `pass` | aws-vault supports both; just a config change. |

**Same principle:** Credentials encrypted at rest, unlocked once per session (per container).

### MFA / TOTP

| | Local | Cloud | Why |
|---|---|---|---|
| TOTP source | 1Password | oathtool + pass | 1Password CLI requires frequent re-auth without biometrics. oathtool generates codes locally from secret stored in pass. |
| MFA script | Calls `op item get ... --otp` | Calls `oathtool --totp --base32 "$(pass show ...)"` | Different tool, same outcome: 6-digit TOTP code. |

**Same principle:** MFA required for AWS access, TOTP secret encrypted at rest.

### Environment & Tooling

| | Local | Cloud | Why |
|---|---|---|---|
| direnv | Yes | Yes | Same |
| mise | Yes | Yes | Same |
| ~/.config/secrets/ | Yes | Yes | Same location, same structure |
| .envrc per project | Yes | Yes | Same |

**No deviation:** These tools are cross-platform and work identically.

### Docker

| | Local | Cloud | Why |
|---|---|---|---|
| Runtime | Docker Desktop | Docker CE + Sysbox | Docker Desktop is macOS-only. Sysbox enables running Docker inside containers without --privileged. |
| Project isolation | Separate directories | Separate containers | Containers provide stronger isolation and match the "instant spin-up" requirement. |

**Same principle:** Each project has isolated Docker environment.

### Secrets Population

| | Local | Cloud | Why |
|---|---|---|---|
| Initial setup | `/setup:credentials` runs `op` to populate ~/.config/secrets/ | Same `op` command on host, then mounted into containers | Identical process, just runs on host instead of directly in dev environment. |
| AWS credentials | `aws-vault add` stores in Keychain | `aws-vault add` stores in pass | Same command, different backend. |
| TOTP secret | Already in 1Password | Must be extracted and stored in pass | One extra step: `pass insert aws/dev-totp` with the TOTP seed. |

### Daily Workflow Differences

| Step | Local | Cloud |
|---|---|---|
| Start of day | Open terminal, cd to project | SSH to host (via Tailscale), `./new-project.sh <name>` |
| First AWS command | Touch ID prompt (Keychain + 1Password) | GPG passphrase prompt (once per container, cached) |
| View web UI | localhost:3000 | http://tailscale-hostname:3100 |
| Switching projects | cd to different directory | Exit container, `./new-project.sh <other>` |
| End of day | Close terminal | Exit container (stays running), disconnect SSH |

### What Stays Exactly The Same

- AWS credential flow (aws-vault -> STS -> short-lived tokens)
- MFA requirement enforced
- direnv loading .envrc on directory entry
- mise managing tool versions
- ~/.config/secrets/ structure and contents
- Environment variables available to applications
- Docker Compose for running services
- Git workflow
- Claude Code with all plugins

### Summary

The cloud setup is a **platform-appropriate translation**, not a compromise. Every security property of the local setup is preserved:

1. Credentials encrypted at rest
2. Single unlock per session (per container)
3. Short-lived AWS tokens via STS
4. MFA required
5. Secrets never in plaintext files or git
6. Per-project environment isolation
