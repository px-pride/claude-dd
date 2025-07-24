#!/bin/bash

# Claude-dd Setup Script
# This script automates the installation of claude-dd

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

echo "======================================"
echo "Claude-dd Setup Script"
echo "======================================"
echo

# Check prerequisites
echo "Checking prerequisites..."

if ! command_exists docker; then
    print_error "Docker is not installed. Please install Docker first."
    exit 1
fi
print_status "Docker is installed"

if ! docker ps >/dev/null 2>&1; then
    print_error "Docker daemon is not running or you don't have permissions."
    print_warning "Try: sudo usermod -aG docker $USER && newgrp docker"
    exit 1
fi
print_status "Docker daemon is accessible"

# Check if claude-dd exists in current directory
if [ ! -f "claude-dd.sh" ]; then
    print_error "claude-dd.sh not found in current directory"
    print_warning "Please run this script from the claude-dd repository directory"
    exit 1
fi
print_status "Found claude-dd.sh"

if [ ! -f "Dockerfile" ]; then
    print_error "Dockerfile not found in current directory"
    exit 1
fi
print_status "Found Dockerfile"

echo
echo "Installing claude-dd..."

# Create ~/.local/bin if it doesn't exist
mkdir -p ~/.local/bin
print_status "Created ~/.local/bin directory"

# Copy claude-dd to ~/.local/bin
cp claude-dd.sh ~/.local/bin/claude-dd
chmod +x ~/.local/bin/claude-dd
print_status "Installed claude-dd to ~/.local/bin/"

# Create ~/claude-docker directory and copy Dockerfile
mkdir -p ~/claude-docker
cp Dockerfile ~/claude-docker/
print_status "Created ~/claude-docker/ and copied Dockerfile"

# Copy prompt file if it exists
if [ -f "claude-dd-prompt.txt" ]; then
    cp claude-dd-prompt.txt ~/claude-docker/
    print_status "Copied claude-dd-prompt.txt"
fi

# Check if ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    print_warning "~/.local/bin is not in your PATH"
    
    # Add to .bashrc
    if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
        print_status "Added ~/.local/bin to PATH in ~/.bashrc"
    fi
    
    # Handle .bash_profile
    if [ -f ~/.bash_profile ]; then
        if ! grep -q "source.*bashrc\|\..*bashrc" ~/.bash_profile; then
            echo -e '\n# Source .bashrc for non-login shells\nif [ -f ~/.bashrc ]; then\n    . ~/.bashrc\nfi' >> ~/.bash_profile
            print_status "Updated ~/.bash_profile to source ~/.bashrc"
        fi
    fi
    
    PATH_UPDATED=true
else
    print_status "~/.local/bin is already in PATH"
    PATH_UPDATED=false
fi

echo
echo "======================================"
echo "Setup Complete!"
echo "======================================"
echo

# Test if claude-dd is accessible
if [ "$PATH_UPDATED" = true ]; then
    print_warning "PATH was updated. You need to reload your shell configuration:"
    echo "   Run: source ~/.bashrc"
    echo "   Or open a new terminal"
    echo
fi

# Check if Claude Code is installed
if command_exists claude; then
    print_status "Claude Code is installed"
else
    print_warning "Claude Code (claude) is not installed"
    echo "   The Docker container will install it, but you may want to install it locally too"
fi

echo "To use claude-dd:"
echo "1. Navigate to any project directory"
echo "2. Run: claude-dd"
echo
echo "First run will build the Docker image (this takes a few minutes)"
echo

# Verify installation
echo "Verifying installation..."
if [ -f ~/.local/bin/claude-dd ] && [ -x ~/.local/bin/claude-dd ]; then
    print_status "claude-dd is installed and executable at ~/.local/bin/claude-dd"
fi

if [ -f ~/claude-docker/Dockerfile ]; then
    print_status "Dockerfile is installed at ~/claude-docker/Dockerfile"
fi

if [ -f ~/claude-docker/claude-dd-prompt.txt ]; then
    print_status "Prompt file is installed at ~/claude-docker/claude-dd-prompt.txt"
fi

echo
print_status "Setup script completed successfully!"