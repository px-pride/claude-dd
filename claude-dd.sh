#!/bin/bash

# Detect if running inside a container
if [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
    IN_CONTAINER=true
    # Get the container ID we're running in
    CURRENT_CONTAINER=$(hostname)
    echo "Running inside container: $CURRENT_CONTAINER"
else
    IN_CONTAINER=false
fi

# Configuration
if [ "$IN_CONTAINER" = true ]; then
    # Inside container: look for Dockerfile in workspace or use passed argument
    if [ -n "$1" ]; then
        DOCKERFILE="$1"
    elif [ -f "/workspace/Dockerfile" ]; then
        DOCKERFILE="/workspace/Dockerfile"
    else
        echo "Error: No Dockerfile found. When running inside a container, pass the Dockerfile path as argument."
        exit 1
    fi
else
    # On host: use standard path
    DOCKERFILE="${1:-$HOME/claude-docker/Dockerfile}"
fi

IMAGE_NAME="claude-ready"

# Generate unique container name based on context
if [ "$IN_CONTAINER" = true ]; then
    # In container, use a nested naming scheme
    PARENT_NAME=$(hostname)
    DIR_NAME=$(basename $(pwd))
    CONTAINER="claude-nested-${DIR_NAME}-$$"
    echo "Container name: $CONTAINER (nested under $PARENT_NAME)"
else
    # On host, use standard naming
    CONTAINER="claude-$(basename $(pwd))"
fi

IMAGE_REBUILT=false

# Function to get host path for current directory when running in container
get_host_workspace_path() {
    if [ "$IN_CONTAINER" = true ]; then
        # Use docker inspect to find where /workspace is mounted from
        docker inspect "$CURRENT_CONTAINER" --format '{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || echo "/workspace"
    else
        echo "$(pwd)"
    fi
}

# Function to get build context path
get_build_context() {
    if [ "$IN_CONTAINER" = true ]; then
        # Inside container, we need to find the host path
        if [ -f "/workspace/Dockerfile" ]; then
            # Dockerfile is in workspace, use host's workspace path
            get_host_workspace_path
        else
            # Dockerfile is elsewhere, use its directory
            dirname "$DOCKERFILE"
        fi
    else
        # On host, use normal dirname
        dirname "$DOCKERFILE"
    fi
}

# Build image if needed
if [ -f "$DOCKERFILE" ]; then
    if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
        echo "Building image with UID=$(id -u)..."
        BUILD_CONTEXT=$(get_build_context)
        docker build -t "$IMAGE_NAME" -f "$DOCKERFILE" --build-arg HOST_UID=$(id -u) "$BUILD_CONTEXT"
        IMAGE_REBUILT=true
    else
        # Check if Dockerfile is newer than image
        IMAGE_DATE=$(docker image inspect -f '{{.Created}}' "$IMAGE_NAME" | xargs date +%s -d)
        FILE_DATE=$(stat -c %Y "$DOCKERFILE" 2>/dev/null || stat -f %m "$DOCKERFILE" 2>/dev/null)
        
        if [ "$FILE_DATE" -gt "$IMAGE_DATE" ]; then
            echo "Dockerfile updated, rebuilding image with UID=$(id -u)..."
            BUILD_CONTEXT=$(get_build_context)
            docker build -t "$IMAGE_NAME" -f "$DOCKERFILE" --build-arg HOST_UID=$(id -u) "$BUILD_CONTEXT"
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
        
        
        if [ -n "$SCRIPT_DATE" ] && [ "$SCRIPT_DATE" -gt "$CONTAINER_DATE" ]; then
            echo "Script updated, recreating container..."           
            CREATE_CONTAINER=true
        fi
    fi
fi

# Create container if needed
if [ "$CREATE_CONTAINER" = true ]; then
    docker rm -f "$CONTAINER" &>/dev/null
    # Create container with SSH mount to root (for proper permissions handling)
    # Build docker run command with conditional mounts
    DOCKER_CMD="docker run -d --name $CONTAINER"
    
    # Handle workspace mount based on context
    if [ "$IN_CONTAINER" = true ]; then
        # Get the host path that corresponds to our /workspace
        HOST_WORKSPACE=$(get_host_workspace_path)
        echo "Mounting host workspace: $HOST_WORKSPACE"
        DOCKER_CMD="$DOCKER_CMD -v $HOST_WORKSPACE:/workspace"
    else
        # Normal host mounting
        DOCKER_CMD="$DOCKER_CMD -v $(pwd):/workspace"
    fi
    
    # Always mount Docker socket
    DOCKER_CMD="$DOCKER_CMD -v /var/run/docker.sock:/var/run/docker.sock"
    
    # Handle SSH and gitconfig mounts only when on host
    if [ "$IN_CONTAINER" = false ]; then
        DOCKER_CMD="$DOCKER_CMD -v $HOME/.ssh:/root/.ssh-host:ro"
        
        # Only mount .gitconfig if it exists as a file
        if [ -f "$HOME/.gitconfig" ]; then
            DOCKER_CMD="$DOCKER_CMD -v $HOME/.gitconfig:/home/claude-user/.gitconfig:ro"
        fi
    fi
    
    DOCKER_CMD="$DOCKER_CMD -w /workspace $IMAGE_NAME tail -f /dev/null"
    
    echo "Running: $DOCKER_CMD"
    eval $DOCKER_CMD
    
    # Set up container based on context
    if [ "$IN_CONTAINER" = false ]; then
        # On host: set up SSH and copy claude-dd script
        docker exec -u root "$CONTAINER" bash -c "
            if [ -d /root/.ssh-host ]; then
                # Remove existing .ssh directory to avoid nested structure
                rm -rf /home/claude-user/.ssh 2>&1
                # Create fresh .ssh directory
                mkdir -p /home/claude-user/.ssh 2>&1
                # Copy contents (not the directory itself) to avoid nesting
                cp -r /root/.ssh-host/* /home/claude-user/.ssh/ 2>&1
                # Set proper ownership and permissions
                chown -R claude-user:claude-user /home/claude-user/.ssh 2>&1
                chmod 700 /home/claude-user/.ssh 2>&1
                find /home/claude-user/.ssh -type f -exec chmod 600 {} \; 2>&1
                # Ensure known_hosts has correct permissions if it exists
                [ -f /home/claude-user/.ssh/known_hosts ] && chmod 644 /home/claude-user/.ssh/known_hosts 2>&1
            fi
            
            # Copy claude-dd script to container if it exists
            if [ -f /workspace/claude-dd.sh ]; then
                cp /workspace/claude-dd.sh /home/claude-user/.local/bin/claude-dd 2>&1
                chmod +x /home/claude-user/.local/bin/claude-dd 2>&1
                chown claude-user:claude-user /home/claude-user/.local/bin/claude-dd 2>&1
            fi
            
            # Copy prompt file if it exists
            if [ -f /workspace/claude-dd-prompt.txt ]; then
                cp /workspace/claude-dd-prompt.txt /home/claude-user/.claude-dd-prompt.txt 2>&1
                chown claude-user:claude-user /home/claude-user/.claude-dd-prompt.txt 2>&1
            fi
        "
    else
        # In container: copy claude-dd from workspace
        docker exec -u root "$CONTAINER" bash -c "
            # Ensure .local/bin exists
            mkdir -p /home/claude-user/.local/bin
            
            # Copy claude-dd script - try multiple locations
            if [ -f /workspace/claude-dd.sh ]; then
                cp /workspace/claude-dd.sh /home/claude-user/.local/bin/claude-dd
            elif [ -f /workspace/claude-dd ]; then
                cp /workspace/claude-dd /home/claude-user/.local/bin/claude-dd
            elif which claude-dd >/dev/null 2>&1; then
                cp \$(which claude-dd) /home/claude-user/.local/bin/claude-dd
            fi
            
            # Set permissions
            if [ -f /home/claude-user/.local/bin/claude-dd ]; then
                chmod +x /home/claude-user/.local/bin/claude-dd
                chown claude-user:claude-user /home/claude-user/.local/bin/claude-dd
            fi
            
            # Copy prompt file if it exists
            if [ -f /workspace/claude-dd-prompt.txt ]; then
                cp /workspace/claude-dd-prompt.txt /home/claude-user/.claude-dd-prompt.txt
                chown claude-user:claude-user /home/claude-user/.claude-dd-prompt.txt
            fi
        "
    fi
else
    # Just ensure container is running
    docker start "$CONTAINER" &>/dev/null
fi

# Execute claude as non-root user with container prompt if available
if docker exec "$CONTAINER" test -f /home/claude-user/.claude-dd-prompt.txt; then
    # Use the prompt file if it exists in the container
    docker exec -it -u claude-user "$CONTAINER" bash -c 'claude --dangerously-skip-permissions "$(cat /home/claude-user/.claude-dd-prompt.txt)"'
else
    # Fallback to no prompt
    docker exec -it -u claude-user "$CONTAINER" claude --dangerously-skip-permissions
fi