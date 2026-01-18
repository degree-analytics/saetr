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
