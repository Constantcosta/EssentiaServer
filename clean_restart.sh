#!/bin/bash
# Clean restart script - ensures NO old processes remain

echo "🧹 Killing all Python and app processes..."
killall -9 MacStudioServerSimulator 2>/dev/null
killall -9 Python 2>/dev/null
sleep 2

echo "✅ Verifying all processes killed..."
if ps aux | grep -E "analyze_server|multiprocessing" | grep -v grep; then
    echo "❌ ERROR: Old processes still running!"
    exit 1
fi

echo "🔨 Building latest code..."
cd /Users/costasconstantinou/Documents/GitHub/EssentiaServer/MacStudioServerSimulator
xcodebuild -scheme MacStudioServerSimulator -configuration Debug build 2>&1 | tail -3

if [ $? -ne 0 ]; then
    echo "❌ BUILD FAILED"
    exit 1
fi

echo "✅ Build succeeded"
echo "🚀 Launching app..."
open "/Users/costasconstantinou/Library/Developer/Xcode/DerivedData/MacStudioServerSimulator-bvbceysesmvoteglccrpuwexhyum/Build/Products/Debug/MacStudioServerSimulator.app"

sleep 3

echo "🔍 Checking server status..."
if curl -s http://127.0.0.1:5050/health 2>&1 | grep -q "healthy"; then
    echo "✅ Server is running and healthy"
    
    # Check for spawn workers (should be NONE)
    if ps aux | grep multiprocessing.spawn | grep -v grep; then
        echo "❌ WARNING: Found spawn workers - using OLD code!"
        exit 1
    else
        echo "✅ No spawn workers - using NEW code"
    fi
else
    echo "⚠️  Server not responding yet (may need manual start in app)"
fi

echo ""
echo "Ready to test! Server should be running with:"
echo "  - No Python multiprocessing"
echo "  - Swift-level parallel requests"
echo "  - All latest code changes"
