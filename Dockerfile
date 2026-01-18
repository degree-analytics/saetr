FROM ubuntu:24.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# System packages
RUN apt-get update && apt-get install -y \
    git \
    curl \
    wget \
    unzip \
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

# Copy AWS CLI GPG key for signature verification
# Key fingerprint: FB5D B77F D5C1 18B8 0511 ADA8 A631 0ACC 4672 475C
# Key expires: 2026-07-07 - update from https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
COPY config/aws-cli-team.gpg /tmp/aws-cli-team.gpg

# Install AWS CLI v2 with GPG signature verification
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip && \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip.sig" -o /tmp/awscliv2.zip.sig && \
    gpg --import /tmp/aws-cli-team.gpg && \
    gpg --verify /tmp/awscliv2.zip.sig /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install && \
    rm -rf /tmp/awscliv2.zip /tmp/awscliv2.zip.sig /tmp/aws /tmp/aws-cli-team.gpg

# Set up locale
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Create dev user with restricted sudo access
# Use UID/GID 1000 to match typical host user for bind mount permissions
# Ubuntu 24.04 has an 'ubuntu' user at UID 1000, so remove it first
# Only grant passwordless sudo for dockerd (required for Docker-in-Docker)
# Other sudo commands will prompt for password (defense in depth)
RUN userdel -r ubuntu 2>/dev/null || true && \
    useradd -m -s /bin/zsh -u 1000 dev && \
    usermod -aG docker dev && \
    echo "dev ALL=(ALL) NOPASSWD: /usr/bin/dockerd" >> /etc/sudoers

# Install mise (runtime version manager) with checksum verification
# Update version and checksum from: https://github.com/jdx/mise/releases
ARG MISE_VERSION=2026.1.4
ARG MISE_SHA256=c19ba5e2f1ffe562655f0c1426b6844e45fe56daf6b796e11d8dca3e070a0698
RUN curl -fsSL "https://github.com/jdx/mise/releases/download/v${MISE_VERSION}/mise-v${MISE_VERSION}-linux-x64.tar.gz" -o /tmp/mise.tar.gz && \
    echo "${MISE_SHA256}  /tmp/mise.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/mise.tar.gz -C /tmp && \
    mv /tmp/mise/bin/mise /usr/local/bin/mise && \
    chmod +x /usr/local/bin/mise && \
    rm -rf /tmp/mise.tar.gz /tmp/mise

# Install aws-vault with checksum verification
ARG AWS_VAULT_VERSION=7.2.0
ARG AWS_VAULT_SHA256=b92bcfc4a78aa8c547ae5920d196943268529c5dbc9c5aca80b797a18a5d0693
RUN wget -q -O /tmp/aws-vault \
    "https://github.com/99designs/aws-vault/releases/download/v${AWS_VAULT_VERSION}/aws-vault-linux-amd64" && \
    echo "${AWS_VAULT_SHA256}  /tmp/aws-vault" | sha256sum -c - && \
    mv /tmp/aws-vault /usr/local/bin/aws-vault && \
    chmod +x /usr/local/bin/aws-vault

# Configure aws-vault to use pass backend
ENV AWS_VAULT_BACKEND=pass

# Install uv (fast Python package manager) with checksum verification
# Update version and checksum from: https://github.com/astral-sh/uv/releases
ARG UV_VERSION=0.9.26
ARG UV_SHA256=30ccbf0a66dc8727a02b0e245c583ee970bdafecf3a443c1686e1b30ec4939e8
RUN curl -fsSL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-x86_64-unknown-linux-gnu.tar.gz" -o /tmp/uv.tar.gz && \
    echo "${UV_SHA256}  /tmp/uv.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/uv.tar.gz -C /tmp && \
    mv /tmp/uv-x86_64-unknown-linux-gnu/uv /usr/local/bin/uv && \
    mv /tmp/uv-x86_64-unknown-linux-gnu/uvx /usr/local/bin/uvx && \
    chmod +x /usr/local/bin/uv /usr/local/bin/uvx && \
    rm -rf /tmp/uv.tar.gz /tmp/uv-x86_64-unknown-linux-gnu

# Install just (command runner) with checksum verification
# Update version and checksum from: https://github.com/casey/just/releases
ARG JUST_VERSION=1.46.0
ARG JUST_SHA256=79966e6e353f535ee7d1c6221641bcc8e3381c55b0d0a6dc6e54b34f9db36eaa
RUN curl -fsSL "https://github.com/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-x86_64-unknown-linux-musl.tar.gz" -o /tmp/just.tar.gz && \
    echo "${JUST_SHA256}  /tmp/just.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/just.tar.gz -C /tmp && \
    mv /tmp/just /usr/local/bin/just && \
    chmod +x /usr/local/bin/just && \
    rm -rf /tmp/just.tar.gz

# Install GitHub CLI (gh)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && \
    apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# Switch to dev user for remaining setup
USER dev
WORKDIR /home/dev

# Set up mise for dev user and install runtimes
RUN /usr/local/bin/mise use -g node@lts && \
    /usr/local/bin/mise use -g python@3.12

# Install Graphite CLI (gt) for stacked branches
RUN /bin/bash -c 'eval "$(/usr/local/bin/mise activate bash)" && npm install -g @withgraphite/graphite-cli'

# Install Claude Code (native installer)
# NOTE: No checksum verification available from Anthropic as of 2025-01
# Accepted risk for convenience; revisit if Anthropic publishes checksums
RUN curl -fsSL https://claude.ai/install.sh | bash

# Create necessary directories
RUN mkdir -p \
    ~/.config/aws-vault \
    ~/.config/secrets \
    ~/.aws \
    ~/.claude/plugins/marketplaces

# Copy dotfiles
COPY --chown=dev:dev dotfiles/zshrc /home/dev/.zshrc
COPY --chown=dev:dev dotfiles/tmux.conf /home/dev/.tmux.conf
COPY --chown=dev:dev dotfiles/envrc /home/dev/.envrc

# Pre-approve direnv configuration (so it doesn't prompt on first shell)
RUN direnv allow /home/dev/.envrc

# Copy AWS vault MFA script
COPY --chown=dev:dev config/oathtool-mfa.sh /home/dev/.config/aws-vault/oathtool-mfa.sh
RUN chmod +x /home/dev/.config/aws-vault/oathtool-mfa.sh

# Note: aws-config is copied at runtime from user's customized version
# Note: dotfiles/gitconfig.template should be customized by user

WORKDIR /home/dev/project

CMD ["sleep", "infinity"]
