#!/bin/bash

# Find the script's directory (workspace root)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Start simulate_load.py in automated unattended mode in the background
echo "Starting simulate_load.py in AUTOMATED UNATTENDED MODE..."
python3 "$SCRIPT_DIR/simulate_load.py" auto &
SIM_PID=$!

# Ensure the load simulator is stopped when this script exits
cleanup() {
    echo "Stopping simulate_load.py (PID: $SIM_PID)..."
    kill "$SIM_PID" 2>/dev/null
    wait "$SIM_PID" 2>/dev/null
}
trap cleanup EXIT INT TERM

# Change directory and run the Vynody app stress test
cd "$SCRIPT_DIR/build/macos/Build/Products/Release"
./Vynody.app/Contents/MacOS/Vynody --stress-test