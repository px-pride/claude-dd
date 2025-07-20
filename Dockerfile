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
    mysql-server \
    mysql-client \
    postgresql \
    postgresql-client \
    postgresql-contrib \
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

# Add claude-user to docker group with matching host GID
RUN groupmod -g 1001 docker && usermod -aG docker claude-user

# Configure MySQL and PostgreSQL to run as claude-user
RUN mkdir -p /etc/mysql/conf.d && \
    echo "[mysqld]\nskip-grant-tables\nuser=claude-user" > /etc/mysql/conf.d/skip-grant.cnf && \
    mkdir -p /etc/postgresql-common && \
    echo "create_main_cluster = false" > /etc/postgresql-common/createcluster.conf && \
    mkdir -p /var/run/mysqld && \
    chown -R claude-user:claude-user /var/run/mysqld /var/lib/mysql && \
    mkdir -p /var/run/postgresql && \
    chown -R claude-user:claude-user /var/run/postgresql /var/lib/postgresql

# Create SSH directory for claude-user with proper permissions
RUN mkdir -p /home/claude-user/.ssh && \
    chmod 700 /home/claude-user/.ssh && \
    chown claude-user:claude-user /home/claude-user/.ssh

# Set working directory
WORKDIR /workspace

# Change ownership of workspace to claude-user
RUN chown claude-user:claude-user /workspace

# Create database startup scripts that don't require sudo
RUN echo '#!/bin/bash\nif [ ! -d "/var/lib/mysql/mysql" ]; then\n  mysqld --initialize-insecure --user=claude-user --datadir=/var/lib/mysql\nfi\nmysqld --user=claude-user --datadir=/var/lib/mysql --socket=/var/run/mysqld/mysqld.sock --pid-file=/var/run/mysqld/mysqld.pid &' > /usr/local/bin/start-mysql && \
    chmod +x /usr/local/bin/start-mysql && \
    echo '#!/bin/bash\nif [ ! -d "/var/lib/postgresql/data" ]; then\n  initdb -D /var/lib/postgresql/data\nfi\npostgres -D /var/lib/postgresql/data &' > /usr/local/bin/start-postgres && \
    chmod +x /usr/local/bin/start-postgres && \
    echo '#!/bin/bash\nmysqladmin -u root -S /var/run/mysqld/mysqld.sock shutdown' > /usr/local/bin/stop-mysql && \
    chmod +x /usr/local/bin/stop-mysql && \
    echo '#!/bin/bash\npg_ctl -D /var/lib/postgresql/data stop' > /usr/local/bin/stop-postgres && \
    chmod +x /usr/local/bin/stop-postgres

# Switch to non-root user
USER claude-user

# Set PATH environment variable globally
ENV PATH="/home/claude-user/.local/bin:$PATH"

# Configure git to trust the workspace directory
RUN git config --global --add safe.directory /workspace

# Add ~/.local/bin to PATH and create .bash_profile
RUN mkdir -p /home/claude-user/.local/bin && \
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> /home/claude-user/.bashrc && \
    printf '# Source .bashrc for login shells\nif [ -f ~/.bashrc ]; then\n    . ~/.bashrc\nfi\n' > /home/claude-user/.bash_profile

# Keep container running
CMD ["tail", "-f", "/dev/null"]