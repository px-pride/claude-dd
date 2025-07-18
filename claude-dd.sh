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

# Check if container needs recreation
RECREATE_NEEDED=false

if docker container inspect "$CONTAINER" &>/dev/null; then
  # Container exists, check if image is newer
  CONTAINER_IMAGE=$(docker container inspect -f '{{.Image}}' "$CONTAINER")
  CURRENT_IMAGE=$(docker image inspect -f '{{.Id}}' "$IMAGE_NAME")
  
  if [ "$CONTAINER_IMAGE" != "$CURRENT_IMAGE" ]; then
    echo "Image updated, recreating container..."
    docker rm -f "$CONTAINER" &>/dev/null
    RECREATE_NEEDED=true
  else
    # Check if claude-dd.sh is newer than container
    CONTAINER_DATE=$(docker container inspect -f '{{.Created}}' "$CONTAINER" | xargs date +%s -d)
    SCRIPT_DATE=$(stat -c %Y "$0" 2>/dev/null || stat -f %m "$0" 2>/dev/null)
    
    if [ "$SCRIPT_DATE" -gt "$CONTAINER_DATE" ]; then
      echo "Script updated, recreating container..."
      docker rm -f "$CONTAINER" &>/dev/null
      RECREATE_NEEDED=true
    fi
  fi
fi

# Try to create container, or start if it exists
# Mount both workspace and SSH directory for git access
docker run -d --name "$CONTAINER" \
  -v $(pwd):/workspace \
  -v $HOME/.ssh:/home/claude-user/.ssh:ro \
  -v $HOME/.gitconfig:/home/claude-user/.gitconfig:ro \
  -w /workspace \
  "$IMAGE_NAME" 2>/dev/null || \
  docker start "$CONTAINER" 2>/dev/null

# Run claude
docker exec -it "$CONTAINER" claude --dangerously-skip-permissions