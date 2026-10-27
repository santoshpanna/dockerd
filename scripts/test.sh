#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

PLUGIN_DIR=""
if ! xcode-select -p 2>/dev/null | grep -q "Xcode"; then
  CANDIDATE="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
  if [ -d "$CANDIDATE" ]; then
    PLUGIN_DIR="$CANDIDATE"
  fi
fi

if [ -n "$PLUGIN_DIR" ]; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGIN_DIR" "$@"
else
  exec swift test "$@"
fi
