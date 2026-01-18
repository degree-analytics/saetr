#!/bin/bash
# =============================================================================
# Saetr - Create or attach to a project container
# =============================================================================
set -e

PROJECT_NAME="$1"
SAETR_DIR="${SAETR_DIR:-$HOME/saetr}"
REGISTRY_FILE="$HOME/.saetr/port-registry.json"
LOCK_FILE="$HOME/.saetr/port-registry.lock"
IMAGE_NAME="${SAETR_IMAGE:-saetr-dev-image:latest}"

# Track if we've registered a port (for cleanup on failure)
REGISTERED_PORT=""

# -----------------------------------------------------------------------------
# Cleanup function - removes registry entry if container creation fails
# -----------------------------------------------------------------------------
cleanup() {
    if [ -n "$REGISTERED_PORT" ]; then
        echo "Cleaning up failed registration..."
        jq --arg name "$PROJECT_NAME" 'del(.[$name])' "$REGISTRY_FILE" > "${REGISTRY_FILE}.tmp" \
            && mv "${REGISTRY_FILE}.tmp" "$REGISTRY_FILE"
    fi
}
trap cleanup EXIT

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
# Port allocation with file locking
# -----------------------------------------------------------------------------
# Use flock to prevent race conditions when multiple instances run concurrently

(
    flock -x 200

    # Find next available port base
    USED_PORTS=$(jq -r 'values[]' "$REGISTRY_FILE" 2>/dev/null | sort -n)
    PORT_BASE=3100

    for used in $USED_PORTS; do
        if [ "$PORT_BASE" -eq "$used" ]; then
            PORT_BASE=$((PORT_BASE + 100))
        fi
    done

    # Verify ports are actually available on the host
    for offset in 0 1 2 3 4 5; do
        port=$((PORT_BASE + offset))
        if ss -tuln 2>/dev/null | grep -q ":${port} "; then
            echo "Error: Port $port is already in use by another process"
            echo "Try a different port range or stop the conflicting service"
            exit 1
        fi
    done

    # Register port assignment
    jq --arg name "$PROJECT_NAME" --argjson port "$PORT_BASE" \
        '. + {($name): $port}' "$REGISTRY_FILE" > "${REGISTRY_FILE}.tmp" \
        && mv "${REGISTRY_FILE}.tmp" "$REGISTRY_FILE"

    # Export for use outside the flock subshell
    echo "$PORT_BASE" > "$HOME/.saetr/.port_base_tmp"

) 200>"$LOCK_FILE"

# Read the allocated port
PORT_BASE=$(cat "$HOME/.saetr/.port_base_tmp")
rm -f "$HOME/.saetr/.port_base_tmp"

# Mark that we've registered (for cleanup trap)
REGISTERED_PORT="$PORT_BASE"

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

# Container created successfully - clear the cleanup flag
REGISTERED_PORT=""

echo "Container created. Attaching..."
docker exec -it "$PROJECT_NAME" zsh
