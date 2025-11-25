#!/bin/bash
# Verify Python environment setup for Essentia server

set -e

echo "=== Python Environment Verification ==="
echo ""

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV_PYTHON="$REPO_ROOT/.venv/bin/python"
SERVER_SCRIPT="$REPO_ROOT/backend/analyze_server.py"

echo "📂 Repository root: $REPO_ROOT"
echo ""

# Check virtual environment
if [ -f "$VENV_PYTHON" ]; then
    echo "✅ Virtual environment Python found: $VENV_PYTHON"
    echo "   Version: $("$VENV_PYTHON" --version)"
else
    echo "❌ Virtual environment Python NOT found at: $VENV_PYTHON"
    echo "   Please run: python3.12 -m venv .venv"
    exit 1
fi

echo ""

# Check Essentia installation
echo "🔍 Checking Essentia installation..."
if "$VENV_PYTHON" -c "import essentia.standard; print('✅ Essentia version:', essentia.__version__)" 2>/dev/null; then
    :
else
    echo "❌ Essentia not installed in virtual environment"
    echo "   Please run: $VENV_PYTHON -m pip install essentia==2.1b6.dev1389"
    exit 1
fi

echo ""

# Check required packages
echo "🔍 Checking required packages..."
"$VENV_PYTHON" -c "
import sys
packages = {
    'librosa': '0.10.1',
    'scipy': '1.10.1',
    'flask': '3.0.0',
    'numpy': None,
    'pandas': None,
    'pyarrow': None,
}

all_good = True
for pkg, expected_version in packages.items():
    try:
        mod = __import__(pkg)
        version = getattr(mod, '__version__', 'unknown')
        if expected_version and version != expected_version:
            print(f'⚠️  {pkg}: {version} (expected {expected_version})')
        else:
            print(f'✅ {pkg}: {version}')
    except ImportError:
        print(f'❌ {pkg}: NOT INSTALLED')
        all_good = False

sys.exit(0 if all_good else 1)
"

echo ""

# Check if server is running and which Python it's using
echo "🔍 Checking running server process..."
if pgrep -f "analyze_server.py" > /dev/null; then
    RUNNING_PYTHON=$(ps aux | grep "[a]nalyze_server.py" | awk '{print $11}')
    echo "⚠️  Server is currently running with: $RUNNING_PYTHON"
    if [ "$RUNNING_PYTHON" = "$VENV_PYTHON" ]; then
        echo "   ✅ Using correct virtual environment Python!"
    else
        echo "   ❌ WRONG PYTHON! Should be using: $VENV_PYTHON"
        echo ""
        echo "   To fix this:"
        echo "   1. Stop the server completely (pkill -f analyze_server.py)"
        echo "   2. Restart from GUI or run: cd $REPO_ROOT && $VENV_PYTHON backend/analyze_server.py"
    fi
else
    echo "   No server process found (this is OK if you haven't started it yet)"
fi

echo ""
echo "=== Verification Complete ==="
