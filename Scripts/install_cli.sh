#!/bin/bash

# GrokCLI Installation Script
# This script builds and installs the GrokCLI tool

set -e  # Exit on any error

echo "==============================================="
echo "GrokCLI Installation Script"
echo "==============================================="

# Determine script location and project root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
COOKIE_EXTRACTOR_PATH="$SCRIPT_DIR/cookie_extractor.py"

echo "📂 Script directory: $SCRIPT_DIR"
echo "📂 Project root: $PROJECT_ROOT"

# Parse command line options
SKIP_COOKIES=false
while getopts ":s" opt; do
  case ${opt} in
    s )
      SKIP_COOKIES=true
      ;;
    \? )
      echo "Invalid option: $OPTARG" 1>&2
      exit 1
      ;;
  esac
done

# Determine installation directory
INSTALL_DIR="$HOME/.local/bin"
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS - check if /usr/local/bin is writable, otherwise use ~/.local/bin
    if [ -w "/usr/local/bin" ]; then
        INSTALL_DIR="/usr/local/bin"
    fi
fi

# Create installation directory if it doesn't exist
mkdir -p "$INSTALL_DIR"

# Navigate to project root for the rest of the process
cd "$PROJECT_ROOT"

# Run cookie extractor first (unless skipped)
if [ "$SKIP_COOKIES" = false ]; then
    echo "🍪 Attempting to extract Grok cookies..."
    # Ensure cookie_extractor.py is executable
    chmod +x "$COOKIE_EXTRACTOR_PATH"
    
    # Run the cookie extractor and capture its exit status
    python "$COOKIE_EXTRACTOR_PATH" --required
    COOKIE_STATUS=$?
    
    if [ $COOKIE_STATUS -ne 0 ]; then
        echo "⚠️  Could not extract Grok cookies!"
        echo "You'll need to authenticate after installation with 'grok auth generate' or 'grok auth import'"
    else
        echo "✅ Successfully extracted Grok cookies!"
    fi
    
    # Small pause to ensure file system catches up
    sleep 1
else
    echo "🍪 Skipping cookie extraction (use -s flag)"
fi

# Clean any previous builds to ensure fresh build
echo "🧹 Cleaning previous builds..."
swift package clean

# Build the CLI in release mode
echo "🔨 Building GrokCLI..."
swift build -c release

# Get the path to the built binary
CLI_PATH=$(swift build -c release --show-bin-path)/grok

# Check if the binary exists
if [ ! -f "$CLI_PATH" ]; then
    echo "❌ Error: Built binary not found at $CLI_PATH"
    echo "This might be because the product name in Package.swift is not 'grok'"
    echo "Looking for alternative binary names..."
    
    # Try to find the binary with a different name
    ALTERNATIVE_CLI_PATH=$(find "$(swift build -c release --show-bin-path)" -type f -perm -u+x -not -name "*.build" -not -name "*.swiftmodule" | head -n 1)
    
    if [ -n "$ALTERNATIVE_CLI_PATH" ]; then
        echo "Found alternative binary at $ALTERNATIVE_CLI_PATH"
        CLI_PATH=$ALTERNATIVE_CLI_PATH
    else
        echo "❌ Could not find any executable in the build directory."
        exit 1
    fi
fi

# Copy the binary to the installation directory
echo "📦 Installing CLI to $INSTALL_DIR/grok..."
cp "$CLI_PATH" "$INSTALL_DIR/grok"

# Make it executable
chmod +x "$INSTALL_DIR/grok"

# Copy cookie_extractor.py to the same directory
echo "📦 Installing cookie_extractor.py to $INSTALL_DIR/cookie_extractor.py..."
cp "$COOKIE_EXTRACTOR_PATH" "$INSTALL_DIR/cookie_extractor.py"
chmod +x "$INSTALL_DIR/cookie_extractor.py"

# Check if the installation directory is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo "⚠️  $INSTALL_DIR is not in your PATH."
    echo "   Add the following line to your shell profile file (e.g., ~/.bash_profile, ~/.zshrc):"
    echo "   export PATH=\"\$PATH:$INSTALL_DIR\""
fi

echo ""
echo "==============================================="
echo "Installation complete!"
echo "-----------------------------------------------"
echo "You can now use the GrokCLI by running: grok"
echo ""
if [ "$SKIP_COOKIES" = false ]; then
    if [ $COOKIE_STATUS -eq 0 ]; then
        echo "✅ Authentication: Cookies were extracted during installation"
        echo "   You can start using grok immediately!"
    else
        echo "⚠️  Authentication: You need to set up authentication:"
        echo "   1. Make sure you're logged in to Grok in your browser"
        echo "   2. Run: grok auth generate"
    fi
else
    echo "⚠️  Authentication: You need to set up authentication:"
    echo "   1. Make sure you're logged in to Grok in your browser"
    echo "   2. Run: grok auth generate" 
fi
echo "===============================================" 