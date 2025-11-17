#!/bin/bash
# Kill orphaned analysis worker processes

echo "🔍 Searching for orphaned Python multiprocessing workers..."

# Count workers before cleanup
WORKER_COUNT=$(ps aux | grep -i "multiprocessing.spawn\|multiprocessing.resource_tracker" | grep -v grep | wc -l | tr -d ' ')

if [ "$WORKER_COUNT" -eq "0" ]; then
    echo "✅ No orphaned workers found"
    exit 0
fi

echo "⚠️  Found $WORKER_COUNT orphaned worker processes"
echo ""
echo "Processes to be killed:"
ps aux | grep -i "multiprocessing.spawn\|multiprocessing.resource_tracker" | grep -v grep | awk '{print "  PID " $2 ": " $11 " " $12 " " $13}'
echo ""

read -p "Kill these processes? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    pkill -9 -f "multiprocessing"
    echo "✅ Killed $WORKER_COUNT worker processes"
    
    # Verify cleanup
    REMAINING=$(ps aux | grep -i "multiprocessing.spawn\|multiprocessing.resource_tracker" | grep -v grep | wc -l | tr -d ' ')
    if [ "$REMAINING" -eq "0" ]; then
        echo "✅ All workers cleaned up successfully"
    else
        echo "⚠️  Warning: $REMAINING workers still running"
    fi
else
    echo "❌ Cancelled"
fi
