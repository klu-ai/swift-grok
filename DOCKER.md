# Docker Setup for GrokProxy

This document provides detailed instructions for running GrokProxy in Docker.

## Prerequisites

- Docker and Docker Compose installed
- Grok account credentials (or access to a browser with an active Grok session)

## Setting Up Credentials

GrokProxy requires valid Grok credentials to function. There are several ways to provide these in Docker:

### Option 1: Use an existing credentials.json file (Recommended)

1. Generate a credentials file using one of these methods:
   - Run `swift run grok auth` on your host machine
   - Run the proxy's setup script: `Scripts/setup_proxy.sh`

2. Place the `credentials.json` file in the project root directory

3. The docker-compose configuration will automatically mount this file into the container

### Option 2: Set environment variables

1. Add your Grok cookies as a JSON string in the `docker-compose.yml` file:

```yaml
environment:
  GROK_COOKIES: '{"x-anonuserid":"your-id","x-challenge":"your-challenge","x-signature":"your-signature","sso":"your-sso","sso-rw":"your-sso-rw"}'
```

### Option 3: Generate on the host, then mount

Browser-cookie extraction runs on the host. Generate or import `credentials.json` before starting Docker, then mount it into the container as `/app/credentials.json`.

## Building and Running

```bash
# Navigate to the project directory
cd path/to/swift-grok

# Build the Docker image
docker compose build

# Run the container
docker compose up
```

## Testing Audio Transcription

When testing `POST /v1/audio/transcriptions` from your host, pass the host path to `curl` and Docker does not need to see the audio file:

```bash
Scripts/test_proxy_transcription.sh ./recording.webm
```

If you run curl or another client from inside the container, mount the audio directory first so the file exists in the container filesystem:

```yaml
services:
  app:
    volumes:
      - ./credentials.json:/app/credentials.json:ro
      - ./test-runs/audio:/audio:ro
```

Then reference the mounted path from inside the container:

```bash
curl http://127.0.0.1:8080/v1/audio/transcriptions \
  -F file=@/audio/recording.webm \
  -F model=whisper-1
```

## How Credentials Are Loaded

The proxy reads credentials when the process starts:

1. At startup, the proxy checks for credentials in this order:
   - `GROK_COOKIES` environment variable
   - Mounted `/app/credentials.json` file

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
2. Try regenerating the credentials with `swift run grok auth`
3. Check the container logs for error messages:
   ```bash
   docker compose logs app
   ```

### Cookie Extraction Fails

If host-side cookie extraction fails:

1. Ensure your browser has an active Grok session
2. Run `Scripts/setup_proxy.sh` or `swift run grok auth` on the host
3. Check that the generated `credentials.json` exists in the project root

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
