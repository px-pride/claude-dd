FROM ubuntu:latest

# Install system dependencies
RUN apt update && apt install -y \
    nodejs \
    npm \
    git \
    python3 \
    python3-pip \
    curl \
    wget \
    vim \
    && apt clean \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code (update this with the correct package name)
RUN npm install -g @anthropic-ai/claude-code

# Set working directory
WORKDIR /workspace

# Keep container running
CMD ["tail", "-f", "/dev/null"]