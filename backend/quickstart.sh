#!/bin/bash
# Quick Start Script for Mac Studio Server Manager
# This script helps you run the standalone macOS server management app

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "🎵 Mac Studio Server Manager - Quick Start"
echo "=========================================="

# Check Python dependencies
echo ""
echo "Checking Python dependencies..."
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is not installed. Please install it first."
    exit 1
fi

echo "✅ Python 3 found: $(python3 --version)"

# Check if dependencies are installed
echo ""
echo "Checking required Python packages..."
MISSING_DEPS=()

for pkg in librosa flask flask-cors numpy requests; do
    if ! python3 -c "import ${pkg//-/_}" 2>/dev/null; then
        MISSING_DEPS+=($pkg)
    fi
done

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo "⚠️  Missing dependencies: ${MISSING_DEPS[*]}"
    echo ""
    read -p "Install missing dependencies? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Installing dependencies..."
        pip3 install "${MISSING_DEPS[@]}"
        echo "✅ Dependencies installed"
    else
        echo "❌ Cannot proceed without dependencies"
        exit 1
    fi
else
    echo "✅ All dependencies installed"
fi

# Check if server is already running
if lsof -Pi :5050 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
    echo ""
    echo "⚠️  Port 5050 is already in use!"
    echo "The server may already be running."
    read -p "Kill existing process and continue? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kill $(lsof -ti:5050) 2>/dev/null || true
        sleep 1
    else
        echo "Please stop the existing server first."
        exit 1
    fi
fi

echo ""
echo "=========================================="
echo "🚀 Ready to start!"
echo ""
echo "Next steps:"
echo "1. Open the project in Xcode"
echo "2. Build and run the ServerManagementView"
echo "3. Click 'Start Server' in the app"
echo ""
echo "Or start the server manually:"
echo "  cd \"$PROJECT_DIR/mac-studio-server\""
echo "  python3 analyze_server.py"
echo ""
echo "📂 Cache location: ~/Music/AudioAnalysisCache/"
echo "🗄️  Database: ~/Music/audio_analysis_cache.db"
echo "=========================================="
