#!/bin/bash

# Build script for GrokProxy
# This script ensures credentials are set up and then builds the proxy

echo "Building GrokProxy..."

# First run the setup script to ensure dependencies and credentials
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup.sh"

if [ -f "$SETUP_SCRIPT" ]; then
    echo "Running setup script..."
    "$SETUP_SCRIPT" || {
        echo "Setup failed. Please fix the issues and try again."
        exit 1
    }
else
    echo "Warning: Setup script not found at $SETUP_SCRIPT"
    
    # Check if credentials.json exists in the root directory
    CREDENTIALS_FILE="../../credentials.json"
    if [ ! -f "$CREDENTIALS_FILE" ]; then
        echo "Warning: credentials.json not found."
        echo "The proxy will start with mock credentials which will likely fail with real requests."
        echo "You may need to run 'swift run grok auth generate' to create credentials."
    fi
fi

# Build the proxy
echo "Building GrokProxy with Swift..."
cd "$(dirname "$SCRIPT_DIR")" || {
    echo "Failed to navigate to project root directory."
    exit 1
}

swift build || {
    echo "Build failed. Please fix the issues and try again."
    exit 1
}

echo "Build successful! You can now run the proxy with 'swift run proxy'" 