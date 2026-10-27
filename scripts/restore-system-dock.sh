#!/bin/bash
set -uo pipefail

defaults delete com.apple.dock autohide-delay 2>/dev/null
defaults delete com.apple.dock autohide 2>/dev/null
killall Dock
echo "System Dock settings restored to defaults."
