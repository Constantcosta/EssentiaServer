#!/bin/bash

# Mac Studio Audio Analysis Server - Setup and Run Script
# This script handles installation and server startup

echo "═══════════════════════════════════════════════════════════"
echo "🎵 Mac Studio Audio Analysis Server Setup"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Determine which Python to use (prefer virtual environment)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VENV_PYTHON="$REPO_ROOT/.venv/bin/python"

if [ -f "$VENV_PYTHON" ]; then
    PYTHON_CMD="$VENV_PYTHON"
    PIP_CMD="$REPO_ROOT/.venv/bin/pip"
    echo "✅ Using virtual environment Python: $PYTHON_CMD"
    echo "   Version: $($PYTHON_CMD --version)"
elif command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
    PIP_CMD="pip3"
    echo "⚠️  Virtual environment not found at $VENV_PYTHON"
    echo "   Using system Python: $(which python3)"
    echo "   Version: $(python3 --version)"
    echo ""
    echo "💡 To use a virtual environment (recommended):"
    echo "   cd $REPO_ROOT && python3 -m venv .venv"
    echo "   $REPO_ROOT/.venv/bin/pip install -r backend/requirements.txt"
else
    echo "❌ Python 3 is not installed. Please install Python 3 first."
    exit 1
fi

echo ""

# Check if pip is available
if ! command -v "$PIP_CMD" &> /dev/null; then
    echo "❌ pip is not installed. Please install pip first."
    exit 1
fi

echo "✅ pip found"
echo ""

# Install required packages
echo "📦 Installing required Python packages..."
echo "   This may take a few minutes on first run..."
echo ""

"$PIP_CMD" install --quiet -r "$SCRIPT_DIR/requirements.txt"

if [ $? -eq 0 ]; then
    echo "✅ All packages installed successfully"
else
    echo "⚠️  Some packages may have had issues. Continuing anyway..."
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "🚀 Starting Audio Analysis Server"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "📂 Database will be created at: ~/Music/audio_analysis_cache.db"
echo "📁 Cache directory: ~/Music/AudioAnalysisCache"
DEFAULT_HOST=${MAC_STUDIO_SERVER_HOST:-0.0.0.0}
DEFAULT_PORT=${MAC_STUDIO_SERVER_PORT:-5050}

export MAC_STUDIO_SERVER_HOST="$DEFAULT_HOST"
export MAC_STUDIO_SERVER_PORT="$DEFAULT_PORT"

if [[ "$DEFAULT_HOST" == "0.0.0.0" ]]; then
    ACCESS_MSG="(accessible to devices on your local network)"
else
    ACCESS_MSG="(localhost only)"
fi

echo "📡 Server will run on: http://${DEFAULT_HOST}:${DEFAULT_PORT} ${ACCESS_MSG}"
echo "💡 Change host/port via MAC_STUDIO_SERVER_HOST / MAC_STUDIO_SERVER_PORT environment variables"
echo ""
echo "💡 The server will auto-analyze 95% of songs accurately"
echo "   You can manually verify/correct the 5% that need it"
echo ""
echo "🔄 Press Ctrl+C to stop the server"
echo ""
echo "═══════════════════════════════════════════════════════════"
echo ""

# Run the server
"$PYTHON_CMD" analyze_server.py
