# Saetr

**Saetr** (Old Norse) — a remote summer mountain farm where work happens independently while the homestead remains free.

A self-hosted platform where agents do the work. Spin up a project, implement a feature, review a PR, run the tests — autonomously. Check in on agents anytime, or use it yourself as a remote dev environment.

## Features

- **Isolated project containers** — Each project runs in its own Sysbox container with full Docker-in-Docker capability
- **Persistent state** — Project files survive container recreation
- **Secure credentials** — GPG-encrypted secrets via `pass`, aws-vault for AWS, API tokens from 1Password
- **Auto-assigned ports** — No port conflicts between projects
- **Browser access** — View web UIs via Tailscale private network
- **Claude Code ready** — Pre-installed with runtime management via mise
- **Verified downloads** — All external binaries (mise, uv, just, aws-vault, Sysbox) verified via SHA256 checksums; AWS CLI verified via GPG signature

### Pre-installed Tools

| Category | Tools |
|----------|-------|
| **Runtimes** | Node.js (LTS), Python 3.12 via mise |
| **Package managers** | npm, uv (Python) |
| **Build tools** | just, make |
| **AWS** | AWS CLI v2, aws-vault |
| **Git & PRs** | git, gh (GitHub CLI), gt (Graphite) |
| **Containers** | Docker, docker-compose |
| **Development** | Claude Code, vim, tmux, direnv |

## Quick Start

### 1. Provision a VPS

Create an Ubuntu 24.04 VPS (recommended: Hetzner CPX21, $9.99/month).

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

# Configure gpg-agent
echo "allow-loopback-pinentry" >> ~/.gnupg/gpg-agent.conf

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
# Docker daemon starts automatically via zshrc

# Your project files are in /home/dev/project
cd /home/dev/project

# First AWS/pass command prompts for GPG passphrase (once per session)
aws-vault exec dev -- aws s3 ls

# Claude Code
claude
```

**Note:** The first command that needs GPG decryption will prompt for your passphrase. After entering it once, gpg-agent caches it for the session.

## Documentation

- [Setup Guide](docs/setup-guide.md) — Detailed installation walkthrough
- [Design Document](docs/design.md) — Architecture and decisions

## Requirements

- VPS: Ubuntu 24.04, 3+ vCPU, 4GB+ RAM (Hetzner CPX21 recommended, $9.99/mo)
- Tailscale account
- 1Password account (optional, for credential extraction)
- AWS account (optional, for ECR/cloud access)

## License

MIT
