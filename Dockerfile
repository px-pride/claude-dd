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

# Create a non-root user (use a different UID to avoid conflicts)
RUN useradd -m -s /bin/bash -u 10001 claude-user

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