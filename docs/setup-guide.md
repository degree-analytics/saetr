# Saetr Setup Guide

Complete walkthrough for setting up your Saetr cloud development environment.

## Prerequisites

- Hetzner Cloud account (or other VPS provider)
- Tailscale account
- 1Password account (for credential extraction)
- SSH key pair

## VPS Provisioning (Hetzner)

1. Go to https://console.hetzner.cloud/
2. Create a new project (e.g., "saetr")
3. Add your SSH public key: Security → SSH Keys → Add SSH Key
4. Create server with the settings below
5. Note the public IP address

### Server Configuration

| Setting | Value | Why |
|---------|-------|-----|
| **Location** | Ashburn, VA | Closest to AWS us-east-2 |
| **Image** | Ubuntu 24.04 | Required for Sysbox (official .deb packages) |
| **Type** | CPX21 ($9.99/mo) or CPX31 ($17.99/mo) | CPX21 minimum; CPX31 for heavier workloads like larger monorepos |
| **SSH Key** | Select yours | Required for root access |
| **Name** | `saetr` | Or whatever you prefer |

### Networking

| Option | Selection | Why |
|--------|-----------|-----|
| **Public IPv4** | ✓ Yes | Needed for initial SSH before Tailscale (~$0.73/mo) |
| **Public IPv6** | ✓ Yes | Free, no downside |
| **Private networks** | ✗ No | Only needed for multi-server setups |

### Additional Options

| Option | Selection | Why |
|--------|-----------|-----|
| **Volumes** | None | 160GB included disk is sufficient; add later if needed |
| **Cloud config** | Leave blank | Our setup script handles everything |

### Plan Sizing

| Plan | Specs | Price | Use Case |
|------|-------|-------|----------|
| CPX21 | 3 vCPU, 4GB RAM, 80GB | $9.99/mo | Light projects, 1-2 active containers |
| CPX31 | 4 vCPU, 8GB RAM, 160GB | $17.99/mo | Heavier stacks (e.g., larger monorepos with Postgres, LocalStack) |

Start with CPX21 and resize if you hit memory limits. Hetzner makes resizing easy.

Verify SSH access:

```bash
ssh root@<IP_ADDRESS>
# Should connect without password
exit
```

## User Account Creation

SSH in as root and create your user:

```bash
ssh root@<IP_ADDRESS>

# Create user (replace <username> with your preferred username)
useradd -m -s /bin/bash <username>
usermod -aG sudo <username>
echo "<username> ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set up SSH for new user
mkdir -p /home/<username>/.ssh
cp ~/.ssh/authorized_keys /home/<username>/.ssh/
chown -R <username>:<username> /home/<username>/.ssh
chmod 700 /home/<username>/.ssh
chmod 600 /home/<username>/.ssh/authorized_keys

exit
```

Reconnect as your user:

```bash
ssh <username>@<IP_ADDRESS>
```

## SSH Key for GitHub (Private Repos)

Set up a passwordless SSH key on the VPS for git operations:

```bash
# Generate passwordless SSH key (no passphrase for convenience)
ssh-keygen -t ed25519 -C "saetr-vps" -N ""

# Display the public key
cat ~/.ssh/id_ed25519.pub

# Pre-populate known_hosts (required since ~/.ssh is mounted read-only)
ssh-keyscan github.com >> ~/.ssh/known_hosts

# For other Git hosts (GitLab, Bitbucket, etc.):
# ssh-keyscan gitlab.com >> ~/.ssh/known_hosts
```

**Note:** `ssh-keyscan` trusts the first key received. For maximum security, verify against official fingerprints: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints

Add the public key to GitHub:
1. Go to https://github.com/settings/keys
2. Click **New SSH key**
3. Title: `saetr-vps`
4. Paste the key and save

**Note:** Keys added to github.com/settings/keys have access to all repos on your account. Use per-device keys (one for the VPS, one for your laptop) so you can revoke individually.

**Security:** Passwordless keys are acceptable here because the VPS is behind Tailscale and this is a dedicated dev key that can be revoked separately from your personal keys.

## Clone and Setup Instructions

```bash
# Clone the repository (use SSH for private repos)
git clone git@github.com:YOUR_ORG/saetr.git ~/saetr
cd ~/saetr

# Run automated setup
./scripts/setup-host.sh
```

The setup script installs Docker, Sysbox, Tailscale, 1Password CLI, Claude Code, and utilities.

Log out and back in after setup for Docker group membership:

```bash
exit
ssh <username>@<IP_ADDRESS>
```

**Verify Sysbox installed correctly:**

```bash
docker info | grep -i runtime
# Should show: sysbox-runc in the list
```

If Sysbox is missing, install manually:

```bash
SYSBOX_VERSION="0.6.4"
wget -q "https://downloads.nestybox.com/sysbox/releases/v${SYSBOX_VERSION}/sysbox-ce_${SYSBOX_VERSION}-0.linux_amd64.deb"
sudo dpkg -i sysbox-ce_${SYSBOX_VERSION}-0.linux_amd64.deb
rm sysbox-ce_${SYSBOX_VERSION}-0.linux_amd64.deb
sudo systemctl restart docker
```

## Tailscale Configuration

```bash
sudo tailscale up
```

Follow the authentication URL. Note your Tailscale hostname (e.g.,
`saetr.tailnet-name.ts.net`).

Verify from your laptop:

```bash
ping saetr.tailnet-name.ts.net
```

## GPG and pass Setup

Generate a GPG key:

```bash
gpg --full-generate-key
```

Choose:
- Key type: **9** (ECC and ECC) - modern alternative to RSA
- Curve: Curve 25519 (if prompted)
- Expiration: 0 (no expiration)
- Name: `saetr-vps` (or your identifier)
- Email: your email
- Passphrase: strong passphrase (store in 1Password)

**Note:** ECC/ed25519 is faster and more secure than RSA. If option 9 isn't available, RSA 4096 is fine.

Note your key ID:

```bash
gpg --list-keys --keyid-format LONG
# Look for the line like: pub   rsa4096/ABCD1234EFGH5678
# ABCD1234EFGH5678 is your key ID
```

Initialize pass:

```bash
pass init <YOUR_GPG_KEY_ID>
```

Configure gpg-agent for better compatibility:

```bash
echo "allow-loopback-pinentry" >> ~/.gnupg/gpg-agent.conf
gpgconf --kill gpg-agent
```

This allows GPG to work in non-interactive contexts (useful for future automation).

## AWS Credentials Configuration

### Create Dedicated IAM User (Recommended)

Create a scoped IAM user for Saetr in your AWS dev account:

1. **IAM → Users → Create user**
   - Name: `saetr-agent`
   - Console access: No

2. **Attach permissions** - Create inline policy with minimum required access:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "ECRReadOnly",
         "Effect": "Allow",
         "Action": [
           "ecr:GetAuthorizationToken",
           "ecr:BatchGetImage",
           "ecr:GetDownloadUrlForLayer",
           "ecr:BatchCheckLayerAvailability"
         ],
         "Resource": "*"
       }
     ]
   }
   ```
   Add permissions as needed for your projects (S3, SES, Secrets Manager, etc.).

3. **Create access key**
   - IAM → Users → saetr-agent → Security credentials → Create access key
   - Use case: "Application running outside AWS"
   - Save the Access Key ID and Secret Access Key

4. **Enable MFA** (recommended)
   - Security credentials → Assign MFA device → Authenticator app
   - Device name: `saetr-agent-mfa` (note the exact name - you'll need it)
   - Click **Show secret key** and copy the TOTP secret (base32 string)
   - Save to 1Password and use for `pass insert aws/dev-totp`

   **Important:** The MFA ARN must match exactly. If you named it `saetr-agent-mfa`, the ARN is:
   ```
   arn:aws:iam::<ACCOUNT_ID>:mfa/saetr-agent-mfa
   ```
   Not `mfa/saetr-agent`. Check IAM console if unsure.

### Add Credentials to Saetr

```bash
aws-vault add dev
# Enter Access Key ID when prompted
# Enter Secret Access Key when prompted
```

Add TOTP secret (get from AWS MFA setup or 1Password):

```bash
pass insert aws/dev-totp
# Paste your TOTP secret (base32 string)
```

Verify TOTP works:

```bash
oathtool --totp --base32 "$(pass show aws/dev-totp)"
# Should output a 6-digit code
```

Configure AWS config:

```bash
cd ~/saetr
cp config/aws-config.template config/aws-config
nano config/aws-config
```

Update these values:
- `YOUR_ACCOUNT_ID` → your 12-digit AWS account ID
- `YOUR_IAM_USER` → `saetr-agent-mfa` (or whatever you named the MFA device)

**Note:** The `config/aws-config` file is for containers (paths use `/home/dev/`). This is correct - containers run as the `dev` user. AWS CLI is not installed on the host and isn't needed.

## 1Password Token Extraction

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

## GitHub and Graphite Tokens

Add tokens to `~/.config/secrets/common.env` for GitHub CLI and Graphite:

```bash
# Append tokens to common.env
cat >> ~/.config/secrets/common.env << 'EOF'
GH_TOKEN=ghp_your_github_personal_access_token
GRAPHITE_TOKEN=your_graphite_token
EOF
```

**Getting the tokens:**
- **GH_TOKEN**: GitHub → Settings → Developer settings → Personal access tokens → Generate new token (classic). Scopes needed: `repo`, `read:org`, `workflow`
- **GRAPHITE_TOKEN**: Run `gt auth` locally and copy token from `~/.config/graphite/user_config`

## Git Configuration

Create `~/.gitconfig` on the host:

```bash
cat > ~/.gitconfig << 'EOF'
[user]
    name = Your Name
    email = your.email@example.com
[init]
    defaultBranch = main
[pull]
    rebase = true
[push]
    autoSetupRemote = true
EOF
```

This is mounted read-only into containers for consistent git identity.

## Claude Code Setup

Claude Code is installed automatically by `setup-host.sh`. You just need to login:

```bash
# Login (opens browser for OAuth)
~/.local/bin/claude login
```

The `~/.claude/` directory is mounted into containers, sharing:
- Subscription authentication
- Plugins (install once, available everywhere)
- Settings

**Plugin management** happens on the host:

```bash
# Clone marketplace and install plugins (on host)
cd ~/.claude/plugins/marketplaces
git clone https://github.com/your-org/secondbrain.git
~/.local/bin/claude plugin install <plugin>@secondbrain

# Updates (on host) - all containers see changes immediately
cd ~/.claude/plugins/marketplaces/secondbrain
git pull
```

## Image Building

```bash
cd ~/saetr
docker build -t saetr-dev-image:latest .
```

This takes a few minutes on first build.

## First Project Creation

```bash
./scripts/new-project.sh my-first-project
```

You're now inside the container. Quick checks:

```bash
whoami          # dev
node --version  # Node.js installed
claude --version # Claude Code installed
```

**GPG Unlock (once per session):**

The first command that needs GPG decryption will prompt for your passphrase:

```bash
# Either of these will trigger the GPG passphrase prompt:
pass show aws/dev-totp           # Direct way to unlock
aws-vault exec dev -- aws sts get-caller-identity  # Or just run AWS command
```

After entering your passphrase once, gpg-agent caches it and subsequent commands work without prompting.

## Daily Workflow

```bash
# From your laptop, SSH via Tailscale
ssh <username>@saetr

# Start or attach to a project
~/saetr/scripts/new-project.sh my-project

# Inside container, work as normal
cd /home/dev/project
git clone https://github.com/you/your-repo.git
cd your-repo
docker compose up -d
claude
```

Access web services from laptop browser:

- http://saetr.tailnet-name.ts.net:3100 (first project)
- http://saetr.tailnet-name.ts.net:3200 (second project)

## Next Steps

### Scheduled Tasks

Sysbox containers run without systemd, so cron is not available inside containers. If you need scheduled tasks:

- **Host-level cron** — Add cron jobs on the VPS host (e.g., nightly image rebuilds)
- **Container-external triggers** — Use `docker exec` from host cron to run commands inside containers
- **Application-level scheduling** — Use your framework's scheduler (Celery Beat, node-cron, etc.)

The `scripts/rebuild-image.sh` script and cron template in `docs/design.md` show the host-level pattern.

## Troubleshooting

### Docker permission denied

Log out and back in to apply group membership:

```bash
exit
ssh <username>@<host>
```

### Sysbox not working

Check Sysbox service and runtime:

```bash
sudo systemctl status sysbox
docker info | grep -i runtime  # Should include sysbox-runc
```

If `sysbox-runc` not listed, see the manual installation steps in "Clone and Setup Instructions" above.

### GPG passphrase prompt every time

The gpg-agent should cache your passphrase. Check if it is running:

```bash
gpg-agent --daemon
```

### Can't reach services from laptop

1. Verify Tailscale is connected on both ends
2. Check container is running: `docker ps`
3. Check port mapping: `list-projects.sh`
4. Verify service is running inside container

### Tailscale hostname not resolving

If `ssh <username>@saetr` doesn't work but Tailscale is connected:
- Use the Tailscale IP directly: `ssh <username>@<TAILSCALE_IP>`
- Enable MagicDNS in Tailscale admin console
- Or use the full hostname: `ssh <username>@saetr.<tailnet>.ts.net`

### aws-vault: "TOTP secret not found"

This error usually means GPG hasn't been unlocked yet. The MFA script can't decrypt the TOTP secret without a cached passphrase.

**Fix:** Run any `pass show` command first to unlock GPG:

```bash
pass show aws/dev-totp  # Enter passphrase when prompted
aws-vault exec dev -- aws sts get-caller-identity  # Now works
```

### MFA validation failed

The MFA ARN in `config/aws-config` must exactly match the MFA device ARN in IAM:
1. Check IAM → Users → saetr-agent → Security credentials → MFA
2. Copy the exact ARN (e.g., `arn:aws:iam::123456789012:mfa/saetr-agent-mfa`)
3. Update `config/aws-config` to match

### GitHub clone permission denied

For private repos, the VPS needs its own SSH key:
1. Check key exists: `ls ~/.ssh/id_ed25519`
2. Check key is added to GitHub: https://github.com/settings/keys
3. Test connection: `ssh -T git@github.com`
