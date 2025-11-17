#!/bin/bash
# Monitor worker activity during calibration

echo "🔍 Monitoring EssentiaServer Workers"
echo "Press Ctrl+C to stop"
echo ""

while true; do
    clear
    date
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 WORKER PROCESSES"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Count Python processes
    MAIN_PROCESS=$(ps aux | grep "[a]nalyze_server.py" | wc -l | tr -d ' ')
    WORKER_PROCESSES=$(ps aux | grep -E "Python.*SpawnProcess" | wc -l | tr -d ' ')
    TOTAL=$((MAIN_PROCESS + WORKER_PROCESSES))
    
    echo "Main Process:    $MAIN_PROCESS"
    echo "Worker Processes: $WORKER_PROCESSES"
    echo "Total Processes:  $TOTAL"
    echo ""
    
    # Show process details
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔧 PROCESS DETAILS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ps aux | grep -E "[Pp]ython.*analyze_server|SpawnProcess" | grep -v grep | \
        awk '{printf "%-8s %5s%% %5s%%  %s\n", $2, $3, $4, substr($0, index($0,$11))}'
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "💻 SYSTEM RESOURCES"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # CPU usage
    CPU_USAGE=$(ps aux | grep -E "[Pp]ython" | awk '{sum+=$3} END {printf "%.1f%%", sum}')
    echo "Total CPU Usage: $CPU_USAGE"
    
    # Memory
    MEM_USAGE=$(ps aux | grep -E "[Pp]ython" | awk '{sum+=$4} END {printf "%.1f%%", sum}')
    echo "Total Memory:    $MEM_USAGE"
    
    echo ""
    echo "Refreshing in 2 seconds..."
    sleep 2
done
