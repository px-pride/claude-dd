# ⚠️ DEPRECATED - Use JailLM Instead

**This project is deprecated. Please use [JailLM](https://github.com/px-pride/jaillm) for a more robust solution.**

---

# Claude Docker Quick Start Guide

## What You Need

Just 3 files:
1. `Dockerfile` - Defines the container environment
2. `claude-dd` - The script that runs everything
3. `README.md` - This guide

## One-Time Setup

1. **Make claude-dd executable and add to PATH:**
   ```bash
   chmod +x claude-dd
   mkdir -p ~/.local/bin
   mv claude-dd ~/.local/bin/
   
   # Add to PATH if needed
   echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
   
   # IMPORTANT: If you have a ~/.bash_profile, it must source ~/.bashrc
   # Check if .bash_profile exists and needs updating:
   if [ -f ~/.bash_profile ] && ! grep -q "source.*bashrc\|\..*bashrc" ~/.bash_profile; then
     echo -e '\n# Source .bashrc for non-login shells\nif [ -f ~/.bashrc ]; then\n    . ~/.bashrc\nfi' >> ~/.bash_profile
   fi
   
   source ~/.bashrc
   ```

2. **Create default Dockerfile location:**
   ```bash
   mkdir -p ~/claude-docker
   cp Dockerfile ~/claude-docker/
   ```

## Daily Usage

```bash
# Navigate to any project
cd ~/projects/my-website

# Run Claude Code (first run builds image & creates container)
claude-dd

# That's it! You're now in Claude Code with --dangerously-skip-permissions
```

### Network Modes

By default, containers use **host network mode** - all ports are automatically accessible from your host system. This is ideal for web development.

```bash
# Default: Host network mode (all ports accessible)
claude-dd

# Port mapping mode: Specify individual ports
claude-dd -p 8000:8000 3001:3001

# Multiple port mappings
claude-dd -p 8080:80 8443:443 3306:3306

# View help
claude-dd -h
```

## How It Works

- First run in a directory creates a container named `claude-[directory-name]`
- Subsequent runs reuse the existing container
- Each directory gets its own isolated container
- Containers persist until you manually remove them
- Databases (MySQL/PostgreSQL) persist in `.claude-dd/` directory

## Multiple Projects

```bash
# Project 1
cd ~/projects/website
claude-dd  # Creates container: claude-website

# Project 2  
cd ~/projects/api
claude-dd  # Creates container: claude-api

# Each project is completely isolated
```

## Custom Dockerfiles

```bash
# Use a different Dockerfile
claude-dd -d ~/my-dockerfiles/Dockerfile.gpu

# Or
claude-dd -d ./Dockerfile.dev

# With port mappings
claude-dd -d ~/my-dockerfiles/Dockerfile.custom -p 8000:8000
```

## Container Management

```bash
# List all claude containers
docker ps -a | grep claude-

# Stop a container
docker stop claude-website

# Remove a container
docker rm claude-website

# Remove all claude containers
docker rm $(docker ps -a | grep claude- | awk '{print $1}')
```

## Updating the Image

If you modify `~/claude-docker/Dockerfile`:
```bash
# The script automatically rebuilds when it detects changes
claude-dd  # Rebuilds image if Dockerfile is newer
```

## Tips

- **Your files are safe** - They're in your normal directories, just mounted into containers
- **Containers persist** - Install tools once, they stay installed in that container
- **Databases persist** - MySQL/PostgreSQL data stored in `.claude-dd/` survives container recreation
- **Performance** - On WSL2, keep projects in the Linux filesystem (not `/mnt/c/`)

## Troubleshooting

**"Unable to find image"**
- First run takes time to build the image
- Check if Docker is running

**"Container name already in use"**  
- A container for this directory already exists
- The script will start it automatically

**Changes to Dockerfile not taking effect**
- The script only rebuilds if Dockerfile is newer than the image
- Force rebuild: `docker rmi claude-ready` then run `claude-dd`
