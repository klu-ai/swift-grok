#!/bin/bash

# Setup script for Swift Grok Client

set -e  # Exit on any error

echo "==============================================="
echo "Swift Grok Client - Build Script"
echo "==============================================="

# Check for Python 3
if command -v python3 &>/dev/null; then
    echo "✅ Python 3 found"
    PYTHON_CMD="python3"
elif command -v python &>/dev/null && python --version 2>&1 | grep -q "Python 3"; then
    echo "✅ Python 3 found"
    PYTHON_CMD="python"
else
    echo "❌ Python 3 not found. Please install Python 3 to use the cookie extractor."
    echo "   Visit https://www.python.org/downloads/ to download and install."
    echo "   Then run this script again."
    exit 1
fi

# Check for pip and install browsercookie
echo "Checking for required Python packages..."
if ! $PYTHON_CMD -c "import browsercookie" &>/dev/null; then
    echo "📦 Installing browsercookie package..."
    $PYTHON_CMD -m pip install browsercookie || {
        echo "❌ Failed to install browsercookie. Please install it manually with:"
        echo "   pip install browsercookie"
        exit 1
    }
else
    echo "✅ browsercookie package already installed"
fi

# Make the cookie extractor executable
chmod +x cookie_extractor.py
echo "✅ Made cookie_extractor.py executable"

# Check if Swift is installed
if command -v swift &>/dev/null; then
    echo "✅ Swift found"
    
    # Get Swift version
    SWIFT_VERSION=$(swift --version | head -n 1 | grep -o 'Swift version [0-9.]*' | sed 's/Swift version //')
    echo "📊 Swift version: $SWIFT_VERSION"
    
    # Check if we're on macOS for Xcode options
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "🔍 Checking Xcode integration options..."
        
        # Modern approach - direct opening in Xcode
        if command -v xed &>/dev/null; then
            echo "💡 Tip: Open this package in Xcode with: xed ."
        else
            echo "💡 Tip: Open this package in Xcode directly with File → Open..."
        fi
        
        # Skip the deprecated generate-xcodeproj command
        echo "ℹ️  Note: 'swift package generate-xcodeproj' is no longer supported in newer Swift versions."
        echo "   Modern Swift packages can be opened directly in Xcode without generating a project file."
    fi
    
    # Build the package
    echo "🔨 Building Swift package..."
    swift build || {
        echo "⚠️ Build failed, but we'll continue with setup."
    }
    
    # Create Tests directory if it doesn't exist
    if [ ! -d "Tests/GrokClientTests" ]; then
        echo "📁 Creating Tests directory..."
        mkdir -p Tests/GrokClientTests
    fi
else
    echo "❓ Swift not found. If you want to build the Swift package, please install Swift:"
    echo "   Visit https://swift.org/download/ for installation instructions."
fi

echo ""
echo "==============================================="
echo "Setup complete! Next steps:"
echo "-----------------------------------------------"
echo "1. Log in to Grok in your browser (Chrome or Firefox)"
echo "2. Run the cookie extractor: ./cookie_extractor.py --required"
echo "3. Add the generated GrokCookies.swift to your project"
echo "4. Use GrokClient in your Swift code"
echo "===============================================" 