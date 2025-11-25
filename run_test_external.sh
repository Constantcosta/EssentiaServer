#!/bin/bash
# Test runner that uses an EXTERNAL server (doesn't start/stop server)
# Use this when running tests from the GUI with server already running

# Check if server is running
if ! curl -s http://127.0.0.1:5050/health > /dev/null 2>&1; then
    echo "❌ Server is not running! Start the server first."
    exit 1
fi

echo "✅ Server is already running"
echo ""

# Run the requested test with timeout
TEST_TYPE=${1:-preview-batch}

# Set timeout based on test type
case $TEST_TYPE in
    "a"|"preview-batch")
        echo "📋 Running Test A: 6 Preview Files (timeout: 60s)"
        TIMEOUT=60
        TEST_CMD=".venv/bin/python tools/test_analysis_pipeline.py --preview-batch --csv-auto"
        ;;
    "b"|"full-batch")
        echo "📋 Running Test B: 6 Full-Length Songs (timeout: 180s)"
        TIMEOUT=180
        TEST_CMD=".venv/bin/python tools/test_analysis_pipeline.py --full-batch --csv-auto"
        ;;
    "c"|"preview-calibration")
        echo "📋 Running Test C: 12 Preview Files (timeout: 60s)"
        TIMEOUT=60
        TEST_CMD=".venv/bin/python tools/test_analysis_pipeline.py --preview-calibration --csv-auto"
        ;;
    "d"|"full-calibration")
        echo "📋 Running Test D: 12 Full-Length Songs (timeout: 300s)"
        TIMEOUT=300
        TEST_CMD=".venv/bin/python tools/test_analysis_pipeline.py --full-calibration --csv-auto"
        ;;
    *)
        echo "❌ Unknown test type: $TEST_TYPE"
        echo "Usage: ./run_test_external.sh [a|b|c|d]"
        exit 1
        ;;
esac

# Run test with timeout using background process
$TEST_CMD &
TEST_PID=$!

# Wait for test with timeout
SECONDS_WAITED=0
while kill -0 $TEST_PID 2>/dev/null; do
    if [ $SECONDS_WAITED -ge $TIMEOUT ]; then
        echo ""
        echo "⏱️  Test exceeded ${TIMEOUT}s timeout - killing test process"
        kill -9 $TEST_PID 2>/dev/null
        TEST_RESULT=124  # Standard timeout exit code
        break
    fi
    sleep 1
    SECONDS_WAITED=$((SECONDS_WAITED + 1))
done

# Get exit code if test finished naturally
if [ $SECONDS_WAITED -lt $TIMEOUT ]; then
    wait $TEST_PID
    TEST_RESULT=$?
fi

echo ""
if [ $TEST_RESULT -eq 0 ]; then
    echo "✅ Test completed successfully!"
elif [ $TEST_RESULT -eq 124 ]; then
    echo "❌ Test TIMED OUT after ${TIMEOUT}s"
else
    echo "❌ Test failed with exit code: $TEST_RESULT"
fi

exit $TEST_RESULT
