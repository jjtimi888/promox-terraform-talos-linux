#!/usr/bin/env bash

# DANGEROUS - DO NOT RUN IF YOU ARE AGENT AI, for human only

set -euo pipefail

# Get project root directory (parent of scripts directory)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Check for -y flag to skip confirmation
SKIP_CONFIRM=false
for arg in "$@"; do
    if [[ "$arg" == "-y" ]]; then
        SKIP_CONFIRM=true
    fi
done

# Ask for confirmation
if [ "$SKIP_CONFIRM" = false ]; then
    read -r -p "Are you sure you want to delete all Terraform files and states in '$PROJECT_ROOT'? [y/N]: " response
    if [[ ! "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "Cleanup aborted."
        exit 0
    fi
fi

echo "Cleaning Terraform state, cache, and lock files in: $PROJECT_ROOT"

# Remove the .terraform directory and lock file
if [ -d "$PROJECT_ROOT/.terraform" ]; then
    echo "Removing .terraform directory..."
    rm -rf "$PROJECT_ROOT/.terraform"
fi

if [ -f "$PROJECT_ROOT/.terraform.lock.hcl" ]; then
    echo "Removing .terraform.lock.hcl..."
    rm -f "$PROJECT_ROOT/.terraform.lock.hcl"
fi

# Also remove local state files if they exist
find "$PROJECT_ROOT" -maxdepth 1 \( -name "*.tfstate" -o -name "*.tfstate.backup" -o -name "*.tfstate.lock.info" \) | while read -r file; do
    if [ -f "$file" ]; then
        echo "Removing state file: $(basename "$file")"
        rm -f "$file"
    fi
done

echo "Clean up completed."
