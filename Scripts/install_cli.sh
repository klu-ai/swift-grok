#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COOKIE_EXTRACTOR="$SCRIPT_DIR/cookie_extractor.py"

usage() {
  cat <<'EOF'
Usage: Scripts/install_cli.sh [options]

Build and install the release grok CLI.

Options:
  --user              Install to ~/.local/bin
  --system            Install to /usr/local/bin
  --bin-dir <dir>     Install to a custom directory
  --prefix <dir>      Install to <dir>/bin
  -s, --skip-auth     Accepted for compatibility; auth is never run by installer
  -h, --help          Show this help

Default install directory:
  /usr/local/bin if writable, otherwise ~/.local/bin
EOF
}

install_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      install_dir="$HOME/.local/bin"
      shift
      ;;
    --system)
      install_dir="/usr/local/bin"
      shift
      ;;
    --bin-dir)
      [[ $# -ge 2 ]] || { echo "Error: --bin-dir requires a directory" >&2; exit 2; }
      install_dir="$2"
      shift 2
      ;;
    --bin-dir=*)
      install_dir="${1#*=}"
      shift
      ;;
    --prefix)
      [[ $# -ge 2 ]] || { echo "Error: --prefix requires a directory" >&2; exit 2; }
      install_dir="$2/bin"
      shift 2
      ;;
    --prefix=*)
      install_dir="${1#*=}/bin"
      shift
      ;;
    -s|--skip-auth)
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$install_dir" ]]; then
  if [[ -d /usr/local/bin && -w /usr/local/bin ]]; then
    install_dir="/usr/local/bin"
  else
    install_dir="$HOME/.local/bin"
  fi
fi

if [[ ! -f "$COOKIE_EXTRACTOR" ]]; then
  echo "Error: missing $COOKIE_EXTRACTOR" >&2
  exit 1
fi

cd "$PROJECT_ROOT"

echo "Building release grok binary..."
swift build -c release --product grok

bin_path="$(swift build -c release --show-bin-path)/grok"
if [[ ! -x "$bin_path" ]]; then
  echo "Error: built binary not found at $bin_path" >&2
  exit 1
fi

ensure_dir() {
  local dir="$1"

  if [[ -d "$dir" ]]; then
    return
  fi

  if mkdir -p "$dir" 2>/dev/null; then
    return
  fi

  command -v sudo >/dev/null 2>&1 || {
    echo "Error: could not create $dir and sudo was not found." >&2
    echo "Try: Scripts/install_cli.sh --user" >&2
    exit 1
  }
  sudo install -d -m 755 "$dir"
}

ensure_dir "$install_dir"

install_file() {
  local src="$1"
  local dest="$2"
  local mode="$3"

  if [[ -w "$(dirname "$dest")" ]]; then
    install -m "$mode" "$src" "$dest"
  else
    command -v sudo >/dev/null 2>&1 || {
      echo "Error: $(dirname "$dest") is not writable and sudo was not found." >&2
      echo "Try: Scripts/install_cli.sh --user" >&2
      exit 1
    }
    sudo install -m "$mode" "$src" "$dest"
  fi
}

install_file "$bin_path" "$install_dir/grok" 755
install_file "$COOKIE_EXTRACTOR" "$install_dir/cookie_extractor.py" 755

cat <<EOF
Installed:
  $install_dir/grok
  $install_dir/cookie_extractor.py

Next:
  1. Add $install_dir to PATH if needed.
  2. Log in to https://grok.com in your browser.
  3. Run: grok auth generate
  4. Try: grok how tall is the moon
EOF

if [[ ":$PATH:" != *":$install_dir:"* ]]; then
  cat <<EOF

PATH update for zsh:
  echo 'export PATH="$install_dir:\$PATH"' >> ~/.zshrc
  exec zsh
EOF
fi
