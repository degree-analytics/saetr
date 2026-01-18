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

# Check if gitconfig exists (avoid Docker creating a directory)
GITCONFIG_MOUNT=""
if [ -f "$HOME/.gitconfig" ]; then
    GITCONFIG_MOUNT="-v $HOME/.gitconfig:/home/dev/.gitconfig:ro"
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
    -v "$HOME/.claude:/home/dev/.claude" \
    -v "$HOME/.ssh:/home/dev/.ssh:ro" \
    $GITCONFIG_MOUNT \
    $AWS_CONFIG_MOUNT \
    -v "${PROJECT_NAME}-data:/home/dev/project" \
    "$IMAGE_NAME" \
    sleep infinity

echo "Container recreated. Attaching..."
docker exec -it "$PROJECT_NAME" zsh
