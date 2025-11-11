#!/bin/bash

# Mac Studio Audio Analysis Server - Setup and Run Script
# This script handles installation and server startup

echo "═══════════════════════════════════════════════════════════"
echo "🎵 Mac Studio Audio Analysis Server Setup"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is not installed. Please install Python 3 first."
    exit 1
fi

echo "✅ Python 3 found: $(python3 --version)"
echo ""

# Check if pip3 is installed
if ! command -v pip3 &> /dev/null; then
    echo "❌ pip3 is not installed. Please install pip3 first."
    exit 1
fi

echo "✅ pip3 found"
echo ""

# Install required packages
echo "📦 Installing required Python packages..."
echo "   This may take a few minutes on first run..."
echo ""

pip3 install --quiet flask flask-cors librosa requests numpy

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
python3 analyze_server.py
