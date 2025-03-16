#!/bin/bash
set -e

# Docker entrypoint script for GrokProxy
# This handles credential generation/validation before starting the app

echo "Starting GrokProxy Docker container..."

# Check if credentials already exist
if [ -f /app/credentials.json ]; then
    echo "Credentials file found at /app/credentials.json"
    # Verify it's a valid JSON file
    if ! python3 -c "import json; json.load(open('/app/credentials.json'))"; then
        echo "Warning: credentials.json appears to be invalid JSON"
    fi
else
    echo "No credentials.json found"
    
    # Check if credentials should be auto-generated
    if [ "$GENERATE_CREDENTIALS" = "true" ]; then
        echo "GENERATE_CREDENTIALS is enabled - attempting to generate credentials"
        
        # Check for browser cookies directories
        CHROME_DIR="/browser-cookies/chrome"
        FIREFOX_DIR="/browser-cookies/firefox"
        
        if [ -d "$CHROME_DIR" ] || [ -d "$FIREFOX_DIR" ]; then
            echo "Browser cookies directory found, attempting to extract credentials"
            python3 /app/cookie_extractor.py --format json --required --output /app/credentials.json || {
                echo "Warning: Failed to generate credentials from browser cookies"
                echo "API requests will likely fail due to missing valid credentials"
            }
        else
            echo "No browser cookies directory mounted and no credentials.json provided"
            echo "API requests will likely fail due to missing valid credentials"
        fi
    else
        echo "Note: Auto-credential generation is disabled"
        echo "If needed, enable by setting GENERATE_CREDENTIALS=true in docker-compose.yml"
    fi
fi

# Check if we need to pass credentials from environment variable
if [ -n "$GROK_COOKIES" ]; then
    echo "Using credentials from GROK_COOKIES environment variable"
fi

# Execute the original command (App serve)
exec "$@" 