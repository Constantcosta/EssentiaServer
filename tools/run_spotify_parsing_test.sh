#!/usr/bin/env zsh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SWIFT_SOURCES=(
  "$REPO_ROOT/MacStudioServerSimulator/MacStudioServerSimulator/SongTitleNormalizer.swift"
  "$REPO_ROOT/MacStudioServerSimulator/MacStudioServerSimulator/SpotifyReferenceData.swift"
  "$SCRIPT_DIR/test_spotify_parsing.swift"
)
TMPDIR=$(mktemp -d)
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

OUTPUT="$TMPDIR/spotify_parsing_test"
/usr/bin/swiftc "${SWIFT_SOURCES[@]}" -o "$OUTPUT"
"$OUTPUT" "$@"
