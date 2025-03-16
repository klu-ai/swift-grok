# Docker Setup for GrokProxy

This document provides detailed instructions for running GrokProxy in Docker.

## Prerequisites

- Docker and Docker Compose installed
- Grok account credentials (or access to a browser with an active Grok session)

## Setting Up Credentials

GrokProxy requires valid Grok credentials to function. There are several ways to provide these in Docker:

### Option 1: Use an existing credentials.json file (Recommended)

1. Generate a credentials file using one of these methods:
   - Run `swift run grok auth generate` on your host machine
   - Run the proxy's setup script: `Sources/GrokProxy/setup.sh`

2. Place the `credentials.json` file in the project root directory

3. The docker-compose configuration will automatically mount this file into the container

### Option 2: Set environment variables

1. Add your Grok cookies as a JSON string in the `docker-compose.yml` file:

```yaml
environment:
  GROK_COOKIES: '{"x-anonuserid":"your-id","x-challenge":"your-challenge","x-signature":"your-signature","sso":"your-sso","sso-rw":"your-sso-rw"}'
```

### Option 3: Auto-generate credentials from browser cookies (Advanced)

This option allows the container to access your browser's cookies to extract Grok credentials:

1. Uncomment the appropriate browser cookie mount in `docker-compose.yml` for your browser and OS:

```yaml
volumes:
  # Choose ONE of these options based on your browser and OS:
  # For Chrome on Linux:
  - ~/.config/google-chrome:/browser-cookies/chrome:ro
  # For Chrome on macOS:
  - ~/Library/Application\ Support/Google/Chrome:/browser-cookies/chrome:ro
  # For Firefox on macOS:
  - ~/Library/Application\ Support/Firefox/Profiles:/browser-cookies/firefox:ro
```

2. Enable auto-generation by uncommenting the `GENERATE_CREDENTIALS` environment variable:

```yaml
environment:
  GENERATE_CREDENTIALS: "true"
```

3. Ensure you're logged into Grok in your browser before building/starting the container

## Building and Running

```bash
# Navigate to the project directory
cd path/to/swift-grok

# Build the Docker image
docker compose -f Sources/GrokProxy/docker-compose.yml build

# Run the container
docker compose -f Sources/GrokProxy/docker-compose.yml up
```

## How Credential Generation Works

The GrokProxy Docker image includes the following credential handling:

1. At container startup, the entrypoint script checks for credentials in this order:
   - Mounted `/app/credentials.json` file
   - `GROK_COOKIES` environment variable
   - Auto-generation from mounted browser cookies (if `GENERATE_CREDENTIALS=true`)

2. If no valid credentials are found, the proxy will start with mock credentials
   and display warning messages in the logs, but API requests will likely fail.

## Customization

### Custom Port

To use a different port, modify the `ports` section in `docker-compose.yml`:

```yaml
ports:
  - '8888:8080'  # Maps container port 8080 to host port 8888
```

### Persistence

The current configuration does not persist Grok conversations. Each Docker container restart will begin with a clean state.

## Troubleshooting

### Authentication Errors

If you see errors like "Invalid credentials" or API requests failing:

1. Verify your credentials.json file contains valid cookies
2. Try regenerating the credentials with `swift run grok auth generate`
3. Check the container logs for error messages:
   ```bash
   docker compose -f Sources/GrokProxy/docker-compose.yml logs
   ```

### Cookie Extraction Fails

If automatic cookie extraction fails:

1. Ensure your browser has an active Grok session
2. Verify the correct browser cookie path is mounted
3. Check that browsercookie package can access your cookies (some browsers encrypt cookies)
4. Try generating credentials on the host machine instead

### Permission Issues

If you see permission denied errors related to credentials:

1. The Docker container runs as the `vapor` user
2. Ensure mounted files are readable by other users:
   ```bash
   chmod 644 credentials.json
   ```

3. You may need to run the container as root for browser cookie access:
   ```yaml
   # In docker-compose.yml
   user: "0"  # Run as root
   ``` 