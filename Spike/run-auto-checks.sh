#!/bin/zsh
# Runs the automated Phase 0 checks and saves output to Spike/logs/auto-<timestamp>.log.
# Run from a terminal app that has Accessibility and Automation -> Finder permission.
# Only creates and closes its own test Finder windows; never runs `killall Finder`.
set -u
cd "$(dirname "$0")"
mkdir -p logs
LOG="logs/auto-$(date +%Y%m%d-%H%M%S).log"
{
  for cmd in "perm" "config" "probe" "s2" "run --strategy all"; do
    echo "===== HideSpike $cmd"
    ./build/HideSpike ${=cmd}
  done
  echo "===== HotkeySpike carbon --listen 10 (press Option+F within 10 s)"
  ./build/HotkeySpike carbon --listen 10
  echo "===== HotkeySpike tap --seconds 10 (type in TextEdit, then press Option+F)"
  ./build/HotkeySpike tap --seconds 10
} 2>&1 | tee "$LOG"
echo
echo "Saved: $PWD/$LOG"
