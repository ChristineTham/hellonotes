#!/bin/zsh
# Relaunch the freshly built Debug HelloNotes.app for live testing.
#
# A HelloNotes process launched before a rebuild keeps running the OLD binary
# (osascript quit / plain `open` reuse it), so UI verification silently tests
# stale code. Force-kill every instance, then launch a NEW instance (-n) of
# the most recently built Debug app from DerivedData.
set -euo pipefail

app=$(ls -td "$HOME"/Library/Developer/Xcode/DerivedData/HelloNotes-*/Build/Products/Debug/HelloNotes.app 2>/dev/null | head -1)
if [[ -z "$app" ]]; then
  echo "No Debug build found in DerivedData — run xcodebuild first." >&2
  exit 1
fi

if pgrep -x HelloNotes >/dev/null; then
  echo "Killing running HelloNotes instance(s): $(pgrep -x HelloNotes | tr '\n' ' ')"
  killall -9 HelloNotes
  sleep 2
fi

echo "Launching $app"
open -n "$app"
sleep 2
pid=$(pgrep -x HelloNotes) || { echo "HelloNotes failed to launch." >&2; exit 1; }
echo "Running: PID $pid ($(ps -o lstart= -p "$pid"))"
