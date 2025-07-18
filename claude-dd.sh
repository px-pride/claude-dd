#!/bin/bash

# Configuration
DOCKERFILE="${1:-$HOME/claude-docker/Dockerfile}"
IMAGE_NAME="claude-ready"
CONTAINER="claude-$(basename $(pwd))"
IMAGE_REBUILT=false

# Build image if needed
if [ -f "$DOCKERFILE" ]; then
    if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
        echo "Building image..."
        docker build -t "$IMAGE_NAME" -f "$DOCKERFILE" "$(dirname "$DOCKERFILE")"
        IMAGE_REBUILT=true
    else
        # Check if Dockerfile is newer than image
        IMAGE_DATE=$(docker image inspect -f '{{.Created}}' "$IMAGE_NAME" | xargs date +%s -d)
        FILE_DATE=$(stat -c %Y "$DOCKERFILE" 2>/dev/null || stat -f %m "$DOCKERFILE" 2>/dev/null)
        
        if [ "$FILE_DATE" -gt "$IMAGE_DATE" ]; then
            echo "Dockerfile updated, rebuilding image..."
            docker build -t "$IMAGE_NAME" -f "$DOCKERFILE" "$(dirname "$DOCKERFILE")"
            IMAGE_REBUILT=true
        fi
    fi
else
    echo "Error: Dockerfile not found at $DOCKERFILE"
    exit 1
fi

# Determine if container needs to be created/recreated
CREATE_CONTAINER=false

if ! docker container inspect "$CONTAINER" &>/dev/null; then
    # Container doesn't exist
    CREATE_CONTAINER=true
else
    # Container exists - check if it needs recreation
    
    if [ "$IMAGE_REBUILT" = true ]; then
        echo "Image was rebuilt, recreating container..."
        CREATE_CONTAINER=true
    else
        # Check if this script is newer than container
        CONTAINER_DATE=$(docker container inspect -f '{{.Created}}' "$CONTAINER" | xargs date +%s -d)
        SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")
        SCRIPT_DATE=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || stat -f %m "$SCRIPT_PATH" 2>/dev/null)
        
        # Debug output
        echo "Debug: Container exists, checking if recreation needed..."
        echo "Debug: Script path: $SCRIPT_PATH"
        echo "Debug: Script date: $SCRIPT_DATE ($(date -d "@$SCRIPT_DATE" 2>/dev/null || echo 'invalid'))"
        echo "Debug: Container date: $CONTAINER_DATE ($(date -d "@$CONTAINER_DATE" 2>/dev/null || echo 'invalid'))"
        
        if [ -n "$SCRIPT_DATE" ] && [ "$SCRIPT_DATE" -gt "$CONTAINER_DATE" ]; then
            echo "Script updated, recreating container..."           
            CREATE_CONTAINER=true
        else
            echo "Debug: No recreation needed (script not newer than container)"
        fi
    fi
fi

# Create container if needed
if [ "$CREATE_CONTAINER" = true ]; then
    docker rm -f "$CONTAINER" &>/dev/null
    echo "Debug: Creating container with mounts:"
    echo "Debug: - Workspace: $(pwd) -> /workspace"
    echo "Debug: - SSH: $HOME/.ssh -> /root/.ssh-host:ro"
    echo "Debug: - Gitconfig: $HOME/.gitconfig -> /home/claude-user/.gitconfig:ro"
    echo "Debug: Checking if source directories exist:"
    [ -d "$HOME/.ssh" ] && echo "Debug: $HOME/.ssh exists" || echo "Debug: WARNING - $HOME/.ssh does NOT exist!"
    [ -f "$HOME/.gitconfig" ] && echo "Debug: $HOME/.gitconfig exists" || echo "Debug: WARNING - $HOME/.gitconfig does NOT exist!"
    # Create container with SSH mount to root (for proper permissions handling)
    docker run -d --name "$CONTAINER" \
        -v $(pwd):/workspace \
        -v $HOME/.ssh:/root/.ssh-host:ro \
        -v $HOME/.gitconfig:/home/claude-user/.gitconfig:ro \
        -w /workspace \
        "$IMAGE_NAME" tail -f /dev/null
    
    # Set up SSH for non-root user with correct permissions
    echo "Debug: Setting up SSH for claude-user..."
    docker exec -u root "$CONTAINER" bash -c "
        echo 'Debug: Inside container SSH setup'
        echo 'Debug: Current user:' \$(whoami)
        echo 'Debug: Checking /root/.ssh-host...'
        if [ -d /root/.ssh-host ]; then
            echo 'Debug: /root/.ssh-host exists'
            ls -la /root/.ssh-host || echo 'Debug: Cannot list /root/.ssh-host'
            echo 'Debug: Copying to /home/claude-user/.ssh...'
            cp -r /root/.ssh-host /home/claude-user/.ssh 2>&1 || echo 'Debug: Copy failed!'
            echo 'Debug: Setting ownership...'
            chown -R claude-user:claude-user /home/claude-user/.ssh 2>&1 || echo 'Debug: Chown failed!'
            echo 'Debug: Setting directory permissions...'
            chmod 700 /home/claude-user/.ssh 2>&1 || echo 'Debug: Chmod 700 failed!'
            echo 'Debug: Setting file permissions...'
            find /home/claude-user/.ssh -type f -exec chmod 600 {} \; 2>&1 || echo 'Debug: Chmod 600 failed!'
            echo 'Debug: Final check - listing .ssh directory:'
            ls -la /home/claude-user/.ssh 2>&1 || echo 'Debug: Cannot list final .ssh directory'
        else
            echo 'Debug: ERROR - /root/.ssh-host does NOT exist!'
            echo 'Debug: Checking what IS in /root:'
            ls -la /root/ 2>&1 || echo 'Debug: Cannot list /root'
            echo 'Debug: Checking mounts:'
            mount | grep ssh || echo 'Debug: No SSH mounts found'
        fi
        echo 'Debug: SSH setup complete'
    "
else
    # Just ensure container is running
    docker start "$CONTAINER" &>/dev/null
fi

# Execute claude as non-root user
docker exec -it -u claude-user "$CONTAINER" claude --dangerously-skip-permissions