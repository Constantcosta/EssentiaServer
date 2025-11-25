#!/bin/bash
# Restart server with correct virtual environment Python

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV_PYTHON="$REPO_ROOT/.venv/bin/python"

echo "=== Restarting Server with Virtual Environment ==="
echo ""

# 1. Kill any existing server processes
echo "🛑 Stopping any existing server processes..."
pkill -f analyze_server.py || echo "   (no server was running)"
sleep 1

# 2. Verify virtual environment
if [ ! -f "$VENV_PYTHON" ]; then
    echo "❌ Virtual environment not found at: $VENV_PYTHON"
    echo "   Please run: python3.12 -m venv .venv"
    exit 1
fi

# 3. Start server with correct Python
echo ""
echo "🚀 Starting server with virtual environment Python..."
echo "   Python: $VENV_PYTHON"
echo "   Version: $($VENV_PYTHON --version)"
echo ""

cd "$REPO_ROOT"
export PYTHONPATH="$REPO_ROOT"
export PYTHONUNBUFFERED=1

exec "$VENV_PYTHON" "$REPO_ROOT/backend/analyze_server.py"
