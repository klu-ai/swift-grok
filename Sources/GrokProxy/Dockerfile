# ================================
# Build image
# ================================
FROM swift:6.0-noble AS build

# Install OS updates and Python for credentials generation
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get install -y libjemalloc-dev python3 python3-pip

# Install Python dependencies for credential extraction
RUN pip3 install browsercookie

# Set up a build area
WORKDIR /build

# First just resolve dependencies.
# This creates a cached layer that can be reused
# as long as your Package.swift/Package.resolved
# files do not change.
COPY ./Package.* ./
RUN swift package resolve \
        $([ -f ./Package.resolved ] && echo "--force-resolved-versions" || true)

# Copy entire repo into container
COPY . .

# Credentials setup - try to generate if not present (requires browser cookies to be mounted)
# This is optional - if credentials.json isn't available, the app will use mock cookies
# Copy credentials.json if it exists externally (preferred method)
RUN if [ -f ./credentials.json ]; then echo "Using existing credentials.json"; else echo "No credentials.json found"; fi

# Attempt to generate credentials from browser cookies if mounted
# Skip with '|| true' to ensure build continues even if this fails
RUN if [ ! -f ./credentials.json ] && [ -d /browser-cookies ] || [ -d /browser-cookies/chrome ] || [ -d /browser-cookies/firefox ]; then \
      echo "Attempting to generate credentials.json from mounted browser cookies" && \
      python3 ./Scripts/cookie_extractor.py --format json --required --output ./credentials.json || true; \
    fi

# Build the application, with optimizations, with static linking, and using jemalloc
# N.B.: The static version of jemalloc is incompatible with the static Swift runtime.
RUN swift build -c release \
        --product App \
        --static-swift-stdlib \
        -Xlinker -ljemalloc

# Switch to the staging area
WORKDIR /staging

# Copy main executable to staging area
RUN cp "$(swift build --package-path /build -c release --show-bin-path)/App" ./

# Copy static swift backtracer binary to staging area
RUN cp "/usr/libexec/swift/linux/swift-backtrace-static" ./

# Copy resources bundled by SPM to staging area
RUN find -L "$(swift build --package-path /build -c release --show-bin-path)/" -regex '.*\.resources$' -exec cp -Ra {} ./ \;

# Copy any resources from the public directory and views directory if the directories exist
# Ensure that by default, neither the directory nor any of its contents are writable.
RUN [ -d /build/Public ] && { mv /build/Public ./Public && chmod -R a-w ./Public; } || true
RUN [ -d /build/Resources ] && { mv /build/Resources ./Resources && chmod -R a-w ./Resources; } || true

# Copy credentials.json (if it exists) to the staging area
RUN [ -f /build/credentials.json ] && cp /build/credentials.json ./ || true

# ================================
# Run image
# ================================
FROM ubuntu:noble

# Make sure all system packages are up to date, and install only essential packages.
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get -q install -y \
      libjemalloc2 \
      ca-certificates \
      tzdata \
      python3 \
      python3-pip \
# If your app or its dependencies import FoundationNetworking, also install `libcurl4`.
      # libcurl4 \
# If your app or its dependencies import FoundationXML, also install `libxml2`.
      # libxml2 \
    && rm -r /var/lib/apt/lists/*

# Install Python dependencies for credential extraction (if needed at runtime)
RUN pip3 install browsercookie

# Create a vapor user and group with /app as its home directory
RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor

# Switch to the new home directory
WORKDIR /app

# Copy built executable and any staged resources from builder
COPY --from=build --chown=vapor:vapor /staging /app

# Copy the Python cookie extractor script to allow runtime generation if needed
COPY --from=build --chown=vapor:vapor /build/Scripts/cookie_extractor.py /app/cookie_extractor.py

# Copy the Docker entrypoint script
COPY --from=build --chown=vapor:vapor /build/Sources/GrokProxy/docker-entrypoint.sh /app/docker-entrypoint.sh

# Provide configuration needed by the built-in crash reporter and some sensible default behaviors.
ENV SWIFT_BACKTRACE=enable=yes,sanitize=yes,threads=all,images=all,interactive=no,swift-backtrace=./swift-backtrace-static

# Ensure all further commands run as the vapor user
USER vapor:vapor

# Let Docker bind to port 8080
EXPOSE 8080

# Use our custom entrypoint script
ENTRYPOINT ["/app/docker-entrypoint.sh"]

# Start the Vapor service when the image is run, default to listening on 8080 in production environment
CMD ["./App", "serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
