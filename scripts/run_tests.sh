#!/usr/bin/env bash

# ==============================================================================
# Vynody Test Runner Script (Memory-safe)
# Prevents memory exhaustion (OOM) on macOS / high-core machines.
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

cd "$PROJECT_ROOT"

# Defaults
CONCURRENCY=${CONCURRENCY:-2}
MAX_HEAP_MB=${MAX_HEAP_MB:-2048}
BATCH_MODE=false
EXTRA_ARGS=()
TARGETS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -j|--concurrency)
      CONCURRENCY="$2"
      shift 2
      ;;
    --batch)
      BATCH_MODE=true
      shift
      ;;
    --heap)
      MAX_HEAP_MB="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: ./scripts/run_tests.sh [options] [test_path...]"
      echo ""
      echo "Options:"
      echo "  -j, --concurrency <N>  Number of concurrent test runners (default: 2)"
      echo "  --batch                Run test directories in batches (utils, player, widgets, pages, audio_core)"
      echo "                         Completely releases process memory between batches."
      echo "  --heap <MB>            Set Dart VM old generation heap limit in MB (default: 2048)"
      echo "  -h, --help             Show this help message"
      echo ""
      echo "Examples:"
      echo "  ./scripts/run_tests.sh                     # Run all tests (including audio_core)"
      echo "  ./scripts/run_tests.sh --batch             # Run in batch mode (lowest memory peak)"
      echo "  ./scripts/run_tests.sh -j 1                # Run sequentially (minimal memory)"
      echo "  ./scripts/run_tests.sh test/utils/         # Run specific directory"
      echo "  ./scripts/run_tests.sh audio_core/test     # Run audio_core tests"
      exit 0
      ;;
    *)
      if [[ "$1" == -* ]]; then
        EXTRA_ARGS+=("$1")
      else
        TARGETS+=("$1")
      fi
      shift
      ;;
  esac
done

# Check for hung lldb-rpc-server on macOS taking huge memory
if [[ "$(uname)" == "Darwin" ]]; then
  LLDB_PID=$(pgrep -f "lldb-rpc-server" 2>/dev/null || true)
  if [[ -n "$LLDB_PID" ]]; then
    echo "⚠️  Detected background 'lldb-rpc-server' running. If memory is tight, consider running: killall lldb-rpc-server"
  fi
fi

# Set Dart VM heap limit to trigger GC proactively
export DART_VM_OPTIONS="--old_gen_heap_size=${MAX_HEAP_MB} ${DART_VM_OPTIONS:-}"

echo "=================================================="
echo "🚀 Running Vynody tests"
echo "   Concurrency: $CONCURRENCY"
echo "   Max Heap:    ${MAX_HEAP_MB} MB"
echo "   Batch Mode:  $BATCH_MODE"
echo "=================================================="

run_flutter_test() {
  local target="$1"
  echo ""
  echo "▶️  Testing: $target"
  flutter test -j "$CONCURRENCY" --no-test-assets "${EXTRA_ARGS[@]}" "$target"
}

run_audio_core_tests() {
  local target="${1:-test}"
  if [ -d "$PROJECT_ROOT/audio_core" ]; then
    echo ""
    echo "▶️  Testing audio_core: $target"
    (
      cd "$PROJECT_ROOT/audio_core"
      flutter test -j "$CONCURRENCY" --no-test-assets "${EXTRA_ARGS[@]}" "$target"
    )
  fi
}

run_test_target() {
  local target="$1"
  if [[ "$target" == audio_core* ]]; then
    local rel_target="${target#audio_core/}"
    if [ "$rel_target" = "audio_core" ] || [ -z "$rel_target" ]; then
      rel_target="test"
    fi
    run_audio_core_tests "$rel_target"
  else
    run_flutter_test "$target"
  fi
}

if [ "$BATCH_MODE" = true ] && [ ${#TARGETS[@]} -eq 0 ]; then
  # Batch execution to release all process memory after each module
  BATCHES=(
    "test/l10n_completeness_test.dart"
    "test/utils"
    "test/player"
    "test/widgets"
    "test/pages"
  )

  for batch in "${BATCHES[@]}"; do
    if [ -e "$batch" ]; then
      run_flutter_test "$batch"
    fi
  done
  run_audio_core_tests "test"
  echo ""
  echo "✅ All test batches (including audio_core) completed successfully!"
else
  # Single run
  if [ ${#TARGETS[@]} -eq 0 ]; then
    run_flutter_test "test"
    run_audio_core_tests "test"
  else
    for target in "${TARGETS[@]}"; do
      run_test_target "$target"
    done
  fi
  echo ""
  echo "✅ Tests completed successfully!"
fi
