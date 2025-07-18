FROM ubuntu:latest

# Install system dependencies and Docker
RUN apt update && apt install -y \
    nodejs \
    npm \
    git \
    python3 \
    python3-pip \
    curl \
    wget \
    vim \
    ca-certificates \
    gnupg \
    lsb-release \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt update \
    && apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
    && apt clean \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code (update this with the correct package name)
RUN npm install -g @anthropic-ai/claude-code

# Accept UID as build argument (defaults to 10001 if not provided)
ARG HOST_UID=10001

# Create a non-root user with the same UID as the host user
# First check if the UID already exists, if so, rename that user
RUN if id -u ${HOST_UID} >/dev/null 2>&1; then \
        existing_user=$(getent passwd ${HOST_UID} | cut -d: -f1); \
        existing_gid=$(id -g ${HOST_UID}); \
        existing_group=$(getent group ${existing_gid} | cut -d: -f1); \
        groupmod -n claude-user ${existing_group}; \
        usermod -l claude-user -d /home/claude-user -m ${existing_user}; \
    else \
        groupadd -g ${HOST_UID} claude-user; \
        useradd -m -s /bin/bash -u ${HOST_UID} -g claude-user claude-user; \
    fi

# Add claude-user to docker group
RUN usermod -aG docker claude-user

# Create SSH directory for claude-user with proper permissions
RUN mkdir -p /home/claude-user/.ssh && \
    chmod 700 /home/claude-user/.ssh && \
    chown claude-user:claude-user /home/claude-user/.ssh

# Set working directory
WORKDIR /workspace

# Change ownership of workspace to claude-user
RUN chown claude-user:claude-user /workspace

# Switch to non-root user
USER claude-user

# Configure git to trust the workspace directory
RUN git config --global --add safe.directory /workspace

# Keep container running
CMD ["tail", "-f", "/dev/null"]