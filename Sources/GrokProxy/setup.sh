#!/bin/bash

# Setup script for GrokProxy
# This script ensures all dependencies are installed and credentials are properly set up

echo "Setting up GrokProxy..."

# Check if Python3 is installed
if ! command -v python3 &> /dev/null; then
    echo "Error: Python3 is required but not installed. Please install Python3 and try again."
    exit 1
fi

# Check and install browsercookie if needed
echo "Checking for required Python packages..."
if ! python3 -c "import browsercookie" &> /dev/null; then
    echo "Installing browsercookie package..."
    pip3 install browsercookie || {
        echo "Error: Failed to install browsercookie. Please install it manually with: pip3 install browsercookie"
        exit 1
    }
    echo "Successfully installed browsercookie."
fi

# Check if credentials.json exists in the root directory
CREDENTIALS_FILE="../../credentials.json"
if [ ! -f "$CREDENTIALS_FILE" ]; then
    echo "credentials.json not found. Attempting to generate it..."
    
    # Check if the cookie_extractor.py script exists
    COOKIE_EXTRACTOR="../../Scripts/cookie_extractor.py"
    if [ ! -f "$COOKIE_EXTRACTOR" ]; then
        echo "Error: cookie_extractor.py not found at $COOKIE_EXTRACTOR"
        exit 1
    fi
    
    # Run the cookie_extractor.py script to generate credentials.json
    python3 "$COOKIE_EXTRACTOR" --format json --required --output "$CREDENTIALS_FILE"
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to generate credentials.json."
        echo "Please ensure you are logged into Grok in your browser and try again."
        exit 1
    fi
    
    echo "Successfully generated credentials.json at $CREDENTIALS_FILE"
else
    echo "credentials.json already exists at $CREDENTIALS_FILE"
fi

echo "Setup complete. You can now build and run GrokProxy." 