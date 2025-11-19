#!/bin/bash
# Simple test runner with automatic server management

echo "🧹 Cleaning up any existing server..."
pkill -f analyze_server.py 2>/dev/null
sleep 1

echo "🚀 Starting server..."
.venv/bin/python backend/analyze_server.py > /tmp/essentia_server.log 2>&1 &
SERVER_PID=$!

echo "⏳ Waiting for server to start..."
sleep 3

# Check if server is running
if ! curl -s http://127.0.0.1:5050/health > /dev/null 2>&1; then
    echo "❌ Server failed to start! Check logs:"
    tail -20 /tmp/essentia_server.log
    kill $SERVER_PID 2>/dev/null
    exit 1
fi

echo "✅ Server is running (PID: $SERVER_PID)"
echo ""

# Run the requested test with timeout
TEST_TYPE=${1:-preview-batch}

# Set timeout based on test type
case $TEST_TYPE in
    "a"|"preview-batch")
        echo "📋 Running Test A: 6 Preview Files (timeout: 30s)"
        TIMEOUT=30
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
        echo "Usage: ./run_test.sh [a|b|c|d]"
        kill $SERVER_PID 2>/dev/null
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
echo "🧹 Stopping server..."
kill $SERVER_PID 2>/dev/null
wait $SERVER_PID 2>/dev/null

# Also kill any worker processes that might be stuck
pkill -9 -f "python.*analysis" 2>/dev/null

if [ $TEST_RESULT -eq 0 ]; then
    echo "✅ Test completed successfully!"
elif [ $TEST_RESULT -eq 124 ]; then
    echo "❌ Test TIMED OUT after ${TIMEOUT}s"
else
    echo "❌ Test failed with exit code: $TEST_RESULT"
fi

# Refresh stable “latest” CSV pointers for the GUI after successful runs
if [ $TEST_RESULT -eq 0 ]; then
    # Find the newest timestamped CSV produced by the test run
    LATEST_CSV=$(ls -t csv/test_results_*.csv 2>/dev/null | head -n 1)
    if [ -n "$LATEST_CSV" ]; then
        echo "ℹ Updating latest CSV pointers from $LATEST_CSV"
        cp "$LATEST_CSV" csv/test_results_latest.csv
        case $TEST_TYPE in
            "c"|"preview-calibration")
                cp "$LATEST_CSV" csv/test_results_c_latest.csv
                META_TARGET="csv/test_results_c_latest.meta.json"
                ;;
            "a"|"preview-batch")
                cp "$LATEST_CSV" csv/test_results_a_latest.csv
                META_TARGET="csv/test_results_a_latest.meta.json"
                ;;
            "b"|"full-batch")
                cp "$LATEST_CSV" csv/test_results_b_latest.csv
                META_TARGET="csv/test_results_b_latest.meta.json"
                ;;
            "d"|"full-calibration")
                cp "$LATEST_CSV" csv/test_results_d_latest.csv
                META_TARGET="csv/test_results_d_latest.meta.json"
                ;;
        esac
        # Write metadata for the GUI to read (commit, branch, timestamp, test type, csv path)
        GIT_COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
        GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        RUN_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        META_FILE="${META_TARGET:-csv/test_results_latest.meta.json}"
        cat > "$META_FILE" <<EOF
{
  "csv": "$(basename "$LATEST_CSV")",
  "csv_path": "$(cd "$(dirname "$LATEST_CSV")" && pwd)/$(basename "$LATEST_CSV")",
  "test_type": "$TEST_TYPE",
  "git_commit": "$GIT_COMMIT",
  "git_branch": "$GIT_BRANCH",
  "run_timestamp_utc": "$RUN_TS"
}
EOF
        echo "RESULT_CSV=$LATEST_CSV"
        echo "RESULT_META=$META_FILE"
        echo "RESULT_COMMIT=$GIT_COMMIT"
    else
        echo "⚠️ No CSV files found to update latest pointers."
    fi
fi

exit $TEST_RESULT
