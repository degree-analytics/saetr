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

# -----------------------------------------------------------------------------
# Checksum verification function
# -----------------------------------------------------------------------------
verify_checksum() {
    local file="$1"
    local expected="$2"
    local actual
    actual=$(sha256sum "$file" | cut -d' ' -f1)
    if [ "$actual" != "$expected" ]; then
        echo "ERROR: Checksum verification failed for $file"
        echo "  Expected: $expected"
        echo "  Got:      $actual"
        rm -f "$file"
        exit 1
    fi
    echo "  Checksum verified: $file"
}

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
    # Use official apt repository with GPG verification (more secure than curl|sh)
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
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
    # SHA256 - verify from https://github.com/nestybox/sysbox/releases when updating
    # To get checksum: wget <url> && sha256sum <file>
    SYSBOX_SHA256="d034ddd364ee1f226b8b1ce7456ea8a12abc2eb661bdf42d3e603ed2dc741827"
    SYSBOX_DEB="sysbox-ce_${SYSBOX_VERSION}-0.linux_amd64.deb"
    wget -q "https://downloads.nestybox.com/sysbox/releases/v${SYSBOX_VERSION}/${SYSBOX_DEB}"
    verify_checksum "$SYSBOX_DEB" "$SYSBOX_SHA256"
    sudo dpkg -i "$SYSBOX_DEB" || sudo apt-get install -f -y
    rm "$SYSBOX_DEB"
    echo "Sysbox installed"
fi

# -----------------------------------------------------------------------------
echo ""
echo "[4/7] Installing Tailscale..."
# -----------------------------------------------------------------------------
if command -v tailscale &>/dev/null; then
    echo "Tailscale already installed"
else
    # Use official apt repository with GPG verification (more secure than curl|sh)
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(. /etc/os-release && echo "$VERSION_CODENAME").noarmor.gpg | \
        sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(. /etc/os-release && echo "$VERSION_CODENAME").tailscale-keyring.list | \
        sudo tee /etc/apt/sources.list.d/tailscale.list
    sudo apt-get update
    sudo apt-get install -y tailscale
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
echo "[6/9] Installing utilities..."
# -----------------------------------------------------------------------------
sudo apt install -y jq oathtool vim htop pass

# -----------------------------------------------------------------------------
echo ""
echo "[7/9] Creating required directories..."
# -----------------------------------------------------------------------------
# These directories are mounted into containers and must exist with correct permissions
# Note: ~/.claude is created by the Claude Code installer in step 9
mkdir -p ~/.ssh && chmod 700 ~/.ssh
mkdir -p ~/.config/secrets && chmod 700 ~/.config/secrets
mkdir -p ~/.saetr
echo "Created ~/.ssh, ~/.config/secrets, ~/.saetr"

# -----------------------------------------------------------------------------
echo ""
echo "[8/9] Installing aws-vault..."
# -----------------------------------------------------------------------------
if command -v aws-vault &>/dev/null; then
    echo "aws-vault already installed"
else
    AWS_VAULT_VERSION="7.2.0"
    # SHA256 from https://github.com/99designs/aws-vault/releases
    AWS_VAULT_SHA256="b92bcfc4a78aa8c547ae5920d196943268529c5dbc9c5aca80b797a18a5d0693"
    AWS_VAULT_BIN="/tmp/aws-vault-${AWS_VAULT_VERSION}"
    wget -q -O "$AWS_VAULT_BIN" \
        "https://github.com/99designs/aws-vault/releases/download/v${AWS_VAULT_VERSION}/aws-vault-linux-amd64"
    verify_checksum "$AWS_VAULT_BIN" "$AWS_VAULT_SHA256"
    sudo mv "$AWS_VAULT_BIN" /usr/local/bin/aws-vault
    sudo chmod +x /usr/local/bin/aws-vault
    echo "aws-vault installed"
fi

# Add aws-vault backend to bashrc if not present
if ! grep -q "AWS_VAULT_BACKEND" ~/.bashrc; then
    echo 'export AWS_VAULT_BACKEND=pass' >> ~/.bashrc
fi

# -----------------------------------------------------------------------------
echo ""
echo "[9/9] Installing Claude Code..."
# -----------------------------------------------------------------------------
if command -v claude &>/dev/null || [ -x "$HOME/.local/bin/claude" ]; then
    echo "Claude Code already installed"
else
    # NOTE: No checksum verification available from Anthropic
    # Accepted risk for convenience; revisit if Anthropic publishes checksums
    curl -fsSL https://claude.ai/install.sh | bash
    echo "Claude Code installed"
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
echo "   - Generate GPG key and initialize pass"
echo "   - Add AWS credentials (aws-vault add dev)"
echo "   - Pull API tokens from 1Password"
echo "   - Add GH_TOKEN and GRAPHITE_TOKEN to ~/.config/secrets/common.env"
echo ""
echo "4. Set up SSH for GitHub (passwordless key for convenience):"
echo "   ssh-keygen -t ed25519 -C 'saetr-vps' -N ''"
echo "   cat ~/.ssh/id_ed25519.pub  # Add to GitHub"
echo "   ssh-keyscan github.com >> ~/.ssh/known_hosts"
echo ""
echo "5. Create ~/.gitconfig with your identity:"
echo "   git config --global user.name 'Your Name'"
echo "   git config --global user.email 'you@example.com'"
echo ""
echo "6. Login to Claude Code:"
echo "   ~/.local/bin/claude login"
echo ""
echo "7. Build the Saetr image:"
echo "   cd ~/saetr"
echo "   docker build -t saetr-dev-image:latest ."
echo ""
echo "8. Create your first project:"
echo "   ./scripts/new-project.sh my-project"
echo ""
