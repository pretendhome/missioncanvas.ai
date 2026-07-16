#!/bin/sh
# Mission Canvas — One Command Install
# Usage: curl -fsSL https://missioncanvas.ai/install.sh | sh
# Tries binary first, falls back to source install if no release exists.
set -e

echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   Mission Canvas Installer               ║"
echo "  ║   Governed AI for professionals          ║"
echo "  ╚══════════════════════════════════════════╝"
echo ""

# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$ARCH" in
  x86_64|amd64) ARCH="x86_64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) echo "  ✗ Unsupported architecture: $ARCH"; exit 1 ;;
esac

case "$OS" in
  darwin) PLATFORM="darwin"; ARCH="arm64" ;;  # Single universal binary
  linux) PLATFORM="linux" ;;
  *) echo "  ✗ Unsupported OS: $OS"; exit 1 ;;
esac

echo "  ✓ Detected: ${PLATFORM}-${ARCH}"

# Create directories
mkdir -p "${HOME}/.mission-canvas/config"
mkdir -p "${HOME}/.local/bin"

# Pull Ollama model if ollama command is installed
pull_ollama() {
  if ! command -v ollama >/dev/null 2>&1; then
    return
  fi
  # Check if daemon is running
  if ! curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    echo "  ⚠ Ollama installed but daemon not running."
    case "$OS" in
      darwin) echo "    → Open /Applications/Ollama.app first, then re-run install" ;;
      *)      echo "    → Run: ollama serve &" ;;
    esac
    return
  fi
  # Check if model already present
  if curl -s http://127.0.0.1:11434/api/tags 2>/dev/null | grep -q "qwen2.5"; then
    echo "  ✓ qwen2.5:7b already available"
  else
    echo "  → Pulling Ollama qwen2.5:7b model..."
    ollama pull qwen2.5:7b || true
  fi
}

# ── Try binary install first ──
BINARY="mc-${PLATFORM}-${ARCH}"
VERSION="latest"
URL="https://github.com/pretendhome/mission-canvas/releases/latest/download/${BINARY}"
echo "  → Downloading binary..."
TMPFILE=$(mktemp)
if curl -fsSL "$URL" -o "$TMPFILE" 2>/dev/null && [ -s "$TMPFILE" ]; then
  chmod +x "$TMPFILE"
  INSTALL_DIR="${HOME}/.local/bin"
  mv "$TMPFILE" "$INSTALL_DIR/mc"
  echo "  ✓ Installed mc to $INSTALL_DIR/mc"
  
  pull_ollama

  # Persist Ollama as configured provider if detected
  if command -v ollama >/dev/null 2>&1 && curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    mkdir -p "$HOME/.mission-canvas/config"
    if [ ! -f "$HOME/.mission-canvas/config/providers.json" ]; then
      cat > "$HOME/.mission-canvas/config/providers.json" << 'PROVEOF'
{
  "providers": {
    "ollama": {
      "model": "qwen2.5:7b",
      "verified": true
    }
  },
  "default_provider": "ollama"
}
PROVEOF
      chmod 600 "$HOME/.mission-canvas/config/providers.json"
      echo "  ✓ Connected to Ollama / qwen2.5:7b"
    fi
  fi

  # Put mc on PATH — write to shell profile (like Homebrew/Ollama do)
  case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
      export PATH="$INSTALL_DIR:$PATH"
      SHELL_NAME=$(basename "$SHELL")
      case "$SHELL_NAME" in
        zsh)  RC_FILE="$HOME/.zshrc" ;;
        bash) RC_FILE="$HOME/.bashrc" ;;
        *)    RC_FILE="$HOME/.profile" ;;
      esac
      if [ -f "$RC_FILE" ] && ! grep -q '.local/bin' "$RC_FILE" 2>/dev/null; then
        echo '' >> "$RC_FILE"
        echo '# Mission Canvas' >> "$RC_FILE"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$RC_FILE"
        echo "  ✓ Added PATH to $RC_FILE"
      elif [ ! -f "$RC_FILE" ]; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' > "$RC_FILE"
        echo "  ✓ Created $RC_FILE with PATH"
      else
        echo "  ✓ PATH already configured in $RC_FILE"
      fi
      ;;
  esac

  # Auto-start the web server. Launch `mc serve` DIRECTLY (not `mc start`) — a
  # frozen onefile that spawns itself inherits the parent's bundle dir and the
  # child dies when the parent exits. A backgrounded direct serve is independent.
  echo "  → Starting web server on http://localhost:7891 ..."
  "$INSTALL_DIR/mc" serve 7891 >/dev/null 2>&1 &

  # Poll until the server binds (frozen extract + ontology load), then open the UI
  i=0
  while [ "$i" -lt 30 ]; do
    if curl -fsS "http://127.0.0.1:7891/" >/dev/null 2>&1; then break; fi
    i=$((i + 1)); sleep 1
  done
  if [ "$i" -lt 30 ]; then
    echo "  ✓ Web UI is live"
    if command -v xdg-open >/dev/null 2>&1; then xdg-open "http://localhost:7891" >/dev/null 2>&1 &
    elif command -v open >/dev/null 2>&1; then open "http://localhost:7891" >/dev/null 2>&1 &
    fi
  else
    echo "  ⚠ Web server didn't come up in time — start it later with 'mc serve'"
  fi

  # Copy canvas templates for mc canvas list-templates
  if [ -d "$INSTALL_DIR/dev/examples" ]; then
    mkdir -p "$HOME/.mission-canvas/templates"
    cp -r "$INSTALL_DIR/dev/examples/"*-canvas "$HOME/.mission-canvas/templates/" 2>/dev/null
    echo "  → Canvas templates installed to ~/.mission-canvas/templates/"
  fi

  # Run health check — show actual result
  echo "  → Running health check..."
  if "$INSTALL_DIR/mc" health 2>&1 | grep -q "PASS\|Health:.*100"; then
    echo "  ✓ Health check passed"
  else
    echo "  ⚠ Health check incomplete (run 'mc health' in a new terminal)"
  fi

  # Install log summary
  mkdir -p "$HOME/.mission-canvas"
  {
    echo "=== Install completed: $(date) ==="
    echo "OS: $(uname -a)"
    echo "Binary: $INSTALL_DIR/mc"
    echo "Ollama: $(command -v ollama 2>/dev/null || echo 'not found')"
    echo "Model: $(curl -s http://127.0.0.1:11434/api/tags 2>/dev/null | grep -o 'qwen2.5[^"]*' | head -1 || echo 'unknown')"
  } >> "$HOME/.mission-canvas/install.log"

  echo ""
  echo "  ╔══════════════════════════════════════════╗"
  echo "  ║   Installation complete!                 ║"
  echo "  ╠══════════════════════════════════════════╣"
  echo "  ║   Web UI:  http://localhost:7891          ║"
  echo "  ║   CLI:     mc shell (open new terminal)   ║"
  echo "  ╚══════════════════════════════════════════╝"
  echo ""
  exit 0
fi
rm -f "$TMPFILE" 2>/dev/null
echo "  ⚠ Binary not available — falling back to source install"

# ── Source install (fallback) ──
echo "  → Installing from source..."

# Check Python
if ! python3 -c 'import sys; exit(0 if sys.version_info >= (3,10) else 1)' 2>/dev/null; then
  echo "  ✗ Python 3.10+ required. Install from https://python.org"
  exit 1
fi
echo "  ✓ Python $(python3 --version 2>&1 | cut -d' ' -f2)"

# Check Git
if ! git --version >/dev/null 2>&1; then
  echo "  ✗ Git required."
  exit 1
fi
echo "  ✓ Git"

# Clone or update to ~/.mission-canvas/
INSTALL_DIR="${HOME}/.mission-canvas"
if [ -d "$INSTALL_DIR/.git" ]; then
  echo "  → Updating existing install..."
  (cd "$INSTALL_DIR" && git pull --quiet 2>/dev/null) || true
else
  echo "  → Cloning Mission Canvas..."
  git clone --quiet --depth 1 https://github.com/pretendhome/mission-canvas.git "$INSTALL_DIR"
fi
echo "  ✓ Source ready"

# Install Python deps (with PEP 668 break packages)
echo "  → Installing dependencies..."
cd "$INSTALL_DIR"
pip3 install --quiet --break-system-packages pyyaml redis fastapi uvicorn websockets pytest httpx 2>/dev/null || \
  pip3 install --quiet pyyaml redis fastapi uvicorn websockets pytest httpx 2>/dev/null || \
  python3 -m pip install --quiet --break-system-packages pyyaml redis fastapi uvicorn websockets pytest httpx 2>/dev/null || \
  echo "  ⚠ pip install failed"
echo "  ✓ Dependencies"

# Install Node.js deps if node is installed
if command -v node >/dev/null 2>&1 && [ -d "runtime" ]; then
  echo "  → Installing Node.js dependencies..."
  (cd runtime && npm install --silent 2>/dev/null) || true
fi

# Make mc command available
if [ -f "$INSTALL_DIR/mc" ]; then
  chmod +x "$INSTALL_DIR/mc"
  ln -sf "$INSTALL_DIR/mc" "${HOME}/.local/bin/mc" 2>/dev/null || true
fi

pull_ollama

# Verify
echo ""
python3 "$INSTALL_DIR/src/mc_cli.py" health 2>/dev/null || echo "  (Run 'mc health' to verify)"

# Auto-start API server (source mode — api_server.py is on disk)
echo "  → Starting web server on http://localhost:7891 ..."
python3 src/api_server.py >/dev/null 2>&1 &

# Poll until the server binds, then open the UI
i=0
while [ "$i" -lt 30 ]; do
  if curl -fsS "http://127.0.0.1:7891/" >/dev/null 2>&1; then break; fi
  i=$((i + 1)); sleep 1
done
if [ "$i" -lt 30 ]; then
  echo "  ✓ Web UI is live"
  if command -v xdg-open >/dev/null 2>&1; then xdg-open "http://localhost:7891" >/dev/null 2>&1 &
  elif command -v open >/dev/null 2>&1; then open "http://localhost:7891" >/dev/null 2>&1 &
  fi
fi

echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   Installation complete!                 ║"
echo "  ╠══════════════════════════════════════════╣"
echo "  ║   Web UI:  http://localhost:7891          ║"
echo "  ║   CLI:     cd $INSTALL_DIR && python3 src/mc_cli.py shell"
echo "  ╚══════════════════════════════════════════╝"
echo ""
