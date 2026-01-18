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
    # Check for dirty worktree before pulling
    if ! git diff --quiet HEAD 2>/dev/null; then
        log "WARNING: Worktree has uncommitted changes - build may use stale code"
        log "  Consider: git stash, or commit your changes"
    fi
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
