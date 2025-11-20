#!/usr/bin/env bash
# One-shot CLI runner for repertoire-90 analysis + accuracy logging.
# Usage: tools/run_repertoire_cli.sh [--allow-cache] [extra analyze_repertoire_90.py flags]
set -eo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="${REPO_ROOT}/reports/repertoire_iterations.log"
ANALYZE_SCRIPT="${REPO_ROOT}/tools/analyze_repertoire_90.py"
ACCURACY_SCRIPT="${REPO_ROOT}/analyze_repertoire_90_accuracy.py"

cd "${REPO_ROOT}"

if [ ! -x ".venv/bin/python" ]; then
  echo "❌ Virtualenv not found at .venv. Please create/activate it first." >&2
  exit 1
fi

# Default to offline mode to avoid HTTP server startup in sandboxed runs.
analysis_args=("$@")
if ! printf '%s\n' "${analysis_args[@]-}" | grep -q -- "--offline"; then
  analysis_args=(--offline "${analysis_args[@]}")
fi

# Quick health check only when running against the HTTP server.
if ! printf '%s\n' "${analysis_args[@]-}" | grep -q -- "--offline"; then
  if ! curl -s --max-time 3 http://127.0.0.1:5050/health >/dev/null; then
    echo "❌ Analyzer server is not reachable on http://127.0.0.1:5050" >&2
    echo "   Start it first (e.g., ./start_server_optimized.sh) or use --offline mode." >&2
    exit 1
  fi
fi

mkdir -p "$(dirname "${LOG_FILE}")"

echo "▶️  Running repertoire analysis via ${ANALYZE_SCRIPT}"
.venv/bin/python "${ANALYZE_SCRIPT}" --csv-auto "${analysis_args[@]}"

echo "▶️  Computing accuracy and appending to ${LOG_FILE}"
.venv/bin/python "${ACCURACY_SCRIPT}" --log --log-file "${LOG_FILE}"

echo "✅ Repertoire iteration complete. Log updated at ${LOG_FILE}"
