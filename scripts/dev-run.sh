#!/bin/bash
# Build, adhoc-sign (unsigned Carbon hotkey registration gets SIGKILLed), run.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build
codesign --force --sign - .build/debug/ClipIsland

# kill previous dev instance
pkill -f '.build/debug/ClipIsland' 2>/dev/null || true
sleep 0.3

if [ "${1:-}" = "--fg" ]; then
    exec .build/debug/ClipIsland
else
    nohup .build/debug/ClipIsland > /tmp/clipisland.log 2>&1 &
    echo "ClipIsland running (log: /tmp/clipisland.log)"
fi
