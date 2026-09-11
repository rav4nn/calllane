#!/bin/bash
# Screenshots the panel in light and dark mode into build/panel-{light,dark}.png.
# The menu bar popover cannot be captured, so the app's --preview window stands in for it.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)

make build

# Only ever touch the preview process this script started: the user's own CallLane is
# a menu bar app that may well be running.
PREVIEW_PID=""
stop_preview() {
    [ -n "$PREVIEW_PID" ] || return 0
    kill "$PREVIEW_PID" 2>/dev/null || true
    wait "$PREVIEW_PID" 2>/dev/null || true
    PREVIEW_PID=""
}
trap stop_preview EXIT

cat > "$ROOT/build/windowid.swift" <<'SWIFT'
import CoreGraphics
import Foundation

// The panel's window id. Matching on the pid of the process this script launched keeps
// a user's own running CallLane, and a window we just killed, out of the picture.
let pid = Int(CommandLine.arguments.dropFirst().first ?? "") ?? -1

func panelWindow() -> Int? {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                             kCGNullWindowID) as? [[String: Any]] ?? []
    let ours = windows.filter {
        $0[kCGWindowOwnerPID as String] as? Int == pid
            && $0[kCGWindowOwnerName as String] as? String == "CallLane"
    }
    let named = ours.first { $0[kCGWindowName as String] as? String == "CallLane Panel Preview" }
    // macOS hides window titles without Screen Recording; fall back to the panel's own size.
    let sized = ours.first { window in
        guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let width = bounds["Width"] as? Double,
              let height = bounds["Height"] as? Double else { return false }
        return width == 300 && height > 100
    }
    return (named ?? sized)?[kCGWindowNumber as String] as? Int
}

// The window is ordered in a moment after launch; give it a few seconds to show up.
for _ in 0..<20 {
    if let id = panelWindow() {
        print(id)
        exit(0)
    }
    Thread.sleep(forTimeInterval: 0.5)
}
exit(1)
SWIFT

snap() {
    local mode=$1
    stop_preview

    # One process per mode: the preview window takes its appearance from this flag, which
    # leaves the user's own Appearance setting untouched.
    "$ROOT/build/CallLane.app/Contents/MacOS/CallLane" --preview "--$mode" >/dev/null 2>&1 &
    PREVIEW_PID=$!
    sleep 2

    local id
    if ! id=$(swift "$ROOT/build/windowid.swift" "$PREVIEW_PID"); then
        echo "error: no CallLane preview window found." >&2
        echo "If the window is on screen, macOS is hiding window titles: grant Screen Recording" >&2
        echo "to your terminal in System Settings → Privacy & Security, then re-run." >&2
        exit 1
    fi

    rm -f "$ROOT/build/panel-$mode.png"
    if ! screencapture -l "$id" -o "$ROOT/build/panel-$mode.png" || [ ! -s "$ROOT/build/panel-$mode.png" ]; then
        echo "error: screencapture produced no image for window $id." >&2
        echo "Check that the display is awake and that your terminal has Screen Recording" >&2
        echo "in System Settings → Privacy & Security." >&2
        exit 1
    fi
    echo "wrote build/panel-$mode.png"
}

# A sleeping display has no window backing store, so screencapture would fail.
caffeinate -u -t 1

snap light
snap dark
