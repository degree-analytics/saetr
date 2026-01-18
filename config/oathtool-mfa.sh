#!/bin/bash
# =============================================================================
# Saetr - TOTP MFA Script for aws-vault
# =============================================================================
# Generates TOTP codes from secrets stored in pass.
# Used by aws-vault's mfa_process configuration.
# =============================================================================

set -euo pipefail

PROFILE="${1:-dev}"
SECRET_PATH="aws/${PROFILE}-totp"

# Check if secret exists
if ! pass show "$SECRET_PATH" &>/dev/null; then
    echo "Error: TOTP secret not found at '$SECRET_PATH'" >&2
    echo "Run: pass insert $SECRET_PATH" >&2
    exit 1
fi

# Generate TOTP code (head -1 handles potential multi-line pass output)
oathtool --totp --base32 "$(pass show "$SECRET_PATH" | head -1)"
