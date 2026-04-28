#!/usr/bin/env bash
# MCP Docker wrapper script - handles authentication and runs MCP server

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <image-name> [additional-args...]" >&2
  exit 1
fi

IMAGE_NAME="$1"
shift  # Remove first argument, rest are passed to container

# Get the script directory to locate .env file
# Since script is in project root, SCRIPT_DIR is the project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
ENV_FILE="$PROJECT_ROOT/.env"

# Load environment variables from .env file
if [ -f "$ENV_FILE" ]; then
  export $(grep -v '^#' "$ENV_FILE" | grep -E '^(GHCR_TOKEN|GHCR_USERNAME|FIGMA_API_KEY|ATLASSIAN_USERNAME|ATLASSIAN_API_KEY)=' | xargs)
fi

# Authenticate with GHCR using the token with SSO authorization
TOKEN="${GHCR_TOKEN}"
USERNAME="${GHCR_USERNAME}"

# Check if credentials are set
if [ -z "$TOKEN" ] || [ -z "$USERNAME" ]; then
  echo "Error: GHCR_TOKEN and GHCR_USERNAME must be set in .env file at $ENV_FILE" >&2
  exit 1
fi

# Login to GHCR (suppress output)
if ! echo "$TOKEN" | docker login ghcr.io -u "$USERNAME" --password-stdin >/dev/null 2>&1; then
  echo "Failed to login to GHCR" >&2
  exit 1
fi

# Pull latest image (suppress output unless error)
if ! docker pull "$IMAGE_NAME" >/dev/null 2>&1; then
  echo "Failed to pull image, using local version" >&2
fi

# Create persistent storage directory for memory server
STORAGE_DIR="${HOME}/.mcp-memory"
mkdir -p "$STORAGE_DIR"

# Run the container with stdio for MCP and persistent volume
# Check image name to determine which env vars to pass
if [[ "$IMAGE_NAME" == *"figma"* ]]; then
  docker run -i --rm -v "${STORAGE_DIR}:/data" -e FIGMA_API_KEY="$FIGMA_API_KEY" "$IMAGE_NAME" "$@"
elif [[ "$IMAGE_NAME" == *"atlassian"* ]]; then
  docker run -i --rm -v "${STORAGE_DIR}:/data" \
    -e CONFLUENCE_URL="https://iagtech.atlassian.net/wiki" \
    -e CONFLUENCE_USERNAME="$ATLASSIAN_USERNAME" \
    -e CONFLUENCE_API_TOKEN="$ATLASSIAN_API_KEY" \
    -e JIRA_URL="https://iagtech.atlassian.net" \
    -e JIRA_USERNAME="$ATLASSIAN_USERNAME" \
    -e JIRA_API_TOKEN="$ATLASSIAN_API_KEY" \
    -e READ_ONLY_MODE="false" \
    -e MCP_VERBOSE="true" \
    "$IMAGE_NAME" "$@"
else
  docker run -i --rm -v "${STORAGE_DIR}:/data" "$IMAGE_NAME" "$@"
fi