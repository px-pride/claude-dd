#!/bin/bash

# Use provided Dockerfile or default location
DOCKERFILE="${1:-$HOME/claude-docker/Dockerfile}"
IMAGE_NAME="claude-ready"

# Container name based on current directory
CONTAINER="claude-$(basename $(pwd))"

# Check if image needs building/rebuilding
BUILD_NEEDED=false

if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
  # Image doesn't exist
  BUILD_NEEDED=true
elif [ -f "$DOCKERFILE" ]; then
  # Image exists, check if Dockerfile is newer
  IMAGE_DATE=$(docker image inspect -f '{{.Created}}' "$IMAGE_NAME" | xargs date +%s -d)
  FILE_DATE=$(stat -c %Y "$DOCKERFILE" 2>/dev/null || stat -f %m "$DOCKERFILE" 2>/dev/null)
  
  if [ "$FILE_DATE" -gt "$IMAGE_DATE" ]; then
    BUILD_NEEDED=true
  fi
fi

# Build if needed
if [ "$BUILD_NEEDED" = true ] && [ -f "$DOCKERFILE" ]; then
  docker build -t "$IMAGE_NAME" -f "$DOCKERFILE" "$(dirname "$DOCKERFILE")"
fi

# Try to create container, or start if it exists
docker run -d --name "$CONTAINER" -v $(pwd):/workspace -w /workspace "$IMAGE_NAME" 2>/dev/null || \
  docker start "$CONTAINER" 2>/dev/null

# Run claude
docker exec -it "$CONTAINER" claude --dangerously-skip-permissions