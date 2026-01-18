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
