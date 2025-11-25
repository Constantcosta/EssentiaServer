#!/bin/bash
# Optimized server startup for Mac Studio M4 Max
# This script loads environment variables and starts the server with optimal settings

cd "$(dirname "$0")"

# Load environment variables from .env
if [ -f .env ]; then
    echo "📝 Loading configuration from .env..."
    set -a
    source .env
    set +a
else
    echo "⚠️  No .env file found, using defaults"
fi

# Display current configuration
echo ""
echo "⚙️  Server Configuration:"
echo "   ANALYSIS_WORKERS: ${ANALYSIS_WORKERS:-2} (parallel song analyses)"
echo "   MAX_CHUNK_BATCHES: ${MAX_CHUNK_BATCHES:-16} (chunk analysis windows)"
echo "   CHUNK_ANALYSIS_SECONDS: ${CHUNK_ANALYSIS_SECONDS:-15}s (per chunk)"
echo "   ANALYSIS_SAMPLE_RATE: ${ANALYSIS_SAMPLE_RATE:-12000}Hz"
echo ""

# Kill any existing server
if pgrep -f "analyze_server.py" > /dev/null; then
    echo "🛑 Stopping existing server..."
    pkill -f analyze_server.py
    sleep 2
fi

# Check if port is free
if lsof -i :5050 | grep -q LISTEN; then
    echo "❌ Port 5050 is still in use. Waiting..."
    sleep 2
    if lsof -i :5050 | grep -q LISTEN; then
        echo "❌ Failed to free port 5050. Manual intervention needed."
        exit 1
    fi
fi

# Activate virtual environment
if [ -d ".venv" ]; then
    source .venv/bin/activate
else
    echo "❌ Virtual environment not found at .venv/"
    exit 1
fi

# Start server in background
echo "🚀 Starting EssentiaServer with optimized settings..."
PYTHONPATH="$(pwd):$PYTHONPATH" .venv/bin/python backend/analyze_server.py &
SERVER_PID=$!

# Wait for server to start
echo "⏳ Waiting for server to initialize..."
sleep 3

# Check if server started successfully
if curl -s http://127.0.0.1:5050/health > /dev/null 2>&1; then
    echo "✅ Server running on http://127.0.0.1:5050"
    echo "   PID: $SERVER_PID"
    echo "   Logs: ~/Library/Logs/EssentiaServer/backend.log"
    echo ""
    echo "📊 Check diagnostics: curl http://127.0.0.1:5050/diagnostics | jq"
    echo "🛑 Stop server: pkill -f analyze_server.py"
else
    echo "❌ Server failed to start. Check logs:"
    echo "   tail -50 ~/Library/Logs/EssentiaServer/backend.log"
    exit 1
fi
