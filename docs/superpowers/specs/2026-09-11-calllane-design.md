# CallLane design

Date: 2026-09-11. Status: approved in a grilling session, pending code.

## Problem

When a macOS app runs a call through Apple's voice-processing audio unit, CoreAudio
lowers every other audio stream on the same output device by about 20 dB. macOS has
no setting for this. Verified on macOS Tahoe 26.6 with AirPods Pro 3: a public
aggregate device that wraps the real output as its only sub-device is not ducked.
A call app set to the aggregate leaves media on the real device at full volume.

Second problem: apps take the Bluetooth microphone and drop AirPods to the low
quality headset profile. Pinning the default input to the built-in mic prevents it.

## Goals

1. Keep one public aggregate output device named `Calls` alive at all times. It wraps
   the current system default output. Call apps select it once, in their own picker.
2. Pin the default input to a device the user chose, and restore that device's input
   volume on every revert.
3. Menu bar app with an output picker, an output volume slider, an input picker with
   a Lock toggle, the `Calls` status line, a setup guide, launch at login, and a
   clean uninstall.
4. Install through a Homebrew cask in the user's own tap, ad-hoc signed, no Developer ID.

## Non-goals

- Per-app volume, routing, EQ, or balance. No process taps. No permission prompts.
- Reverse mode for apps with no speaker picker, such as Meet in Safari.
- Naming the app that uses `Calls`. CoreAudio only exposes "in use somewhere".
- Notifications. All state is shown in the menu.

## Decisions

| Decision | Choice |
| --- | --- |
| Distribution | Cask in `rav4nn/homebrew-tap`, installed with `--no-quarantine` |
| Scope | Switcher: output + volume, input + lock, Calls status, setup guide |
| Calls wraps | The system default output, always. No setting. |
| Device name | `Calls`, fixed. UID `dev.rav4nn.calllane.calls`, fixed. |
| Input lock | Lock to a chosen input UID. Revert on change if present. Restore its input volume. |
| Calls as default | Auto-revert to the wrapped device. Show one status line. |
| Onboarding | Setup window at first launch and from the menu. "In use" dot in the menu bar. |
| Minimum macOS | 14 |
| Build | Swift Package, Makefile assembles the bundle. No Xcode project. No dependencies. |
| Release | GitHub Actions on tag: build, `codesign -s -`, zip, attach to release. |
| Name, license | CallLane, MIT, `github.com/rav4nn/calllane` |

## Architecture

Three units, one process, no daemon. The app is the daemon; launch at login keeps it up.

### AudioSystem (CoreAudio wrapper, ~200 lines)

Pure functions over `AudioObjectID`. No state. Provides:

- `devices() -> [Device]` with id, uid, name, transport, hasInput, hasOutput
- `defaultOutput()`, `defaultInput()`, `setDefaultOutput(id)`, `setDefaultInput(id)`
- `outputVolume(id) -> Float?`, `setOutputVolume(id, Float)`; same for input.
  Reads the main element scalar volume first, falls back to channel 1 and 2.
  Returns nil when the device has no volume control, such as an aggregate.
- `isRunningSomewhere(id) -> Bool` from `kAudioDevicePropertyDeviceIsRunningSomewhere`
- `createAggregate(name, uid, subDeviceUID) -> AudioObjectID`,
  `setAggregateSubDevice(id, subDeviceUID)`, `destroyAggregate(id)`,
  `aggregateSubDeviceUID(id) -> String?`
- `listen(selector, on object, handler)` registers a property listener block on the
  main queue and returns a token to remove it.

### Controller (`@Observable`, ~150 lines)

Owns the rules. Holds the device list, current defaults, lock state, and Calls state.
Listens to three properties on the system object: device list, default output,
default input. On each event it runs `reconcile()`:

1. Refresh the device list.
2. Calls device: if absent, create it with the current default output as sub-device.
   If the default output is `Calls` itself, set the default output back to the device
   `Calls` wraps and set `status = "Calls is for call apps only. Output set back to X."`
   Otherwise, if `Calls` wraps a device other than the default output, rewrite the
   sub-device list to the default output.
3. Input lock: if locked, and the locked device is present, and it is not the default
   input, set it as default input and set its input volume to the stored level.
4. Refresh `callsInUse` from `isRunningSomewhere`.

`reconcile()` is idempotent, so re-entrant events from its own writes converge.
A 200 ms coalescing timer collapses the event burst that follows a Bluetooth connect.

Persisted in `UserDefaults`: `lockedInputUID`, `lockedInputVolume`, `setupShown`.

### Menu UI (SwiftUI `MenuBarExtra`, ~150 lines)

Menu bar icon: a phone-in-lane glyph; a dot overlay when `callsInUse` is true.

Menu, top to bottom:

- Output section: one row per output device except `Calls`, check on the default,
  a volume slider under the list. Slider disabled when the default has no volume control.
- Input section: one row per input device, check on the default, a Lock toggle.
- Calls line: `Calls → AirPods Pro 3 · in use` or `· idle`, plus the status message.
- Setup guide… opens the setup window.
- Launch at login toggle, through `SMAppService`.
- Remove Calls device and quit. Destroys the aggregate and quits.
- Quit. Leaves the device in place, so call apps keep working until next launch.

Setup window: one section per app with the exact menu path. FaceTime, Zoom, Google
Meet in Chrome, Slack, Microsoft Teams, Discord, WhatsApp. Text only.

## Data flow

CoreAudio property event → listener block → coalescing timer → `reconcile()` →
CoreAudio writes → `@Observable` state → SwiftUI menu. User actions in the menu call
the same setters and then `reconcile()`.

## Error handling

- Every CoreAudio call returns `OSStatus`. Failures are logged with `os.Logger` and
  shown in the status line when they affect the user, such as "Could not create Calls".
- Aggregate creation with no output device present is skipped and retried on the next
  device list event.
- If the locked input device is absent, the lock stays on and does nothing.
- On quit, no cleanup. On "Remove Calls device and quit", destroy then quit.

## Testing

- `AudioSystem` is exercised by `Tests/CallLaneTests/AudioSystemTests.swift`: create
  an aggregate with a throwaway UID around the current default output, read back its
  sub-device, rewrite it, destroy it. Runs on any Mac with an output device.
- `Controller` rules are tested with a fake `AudioSystem` protocol implementation:
  Calls selected as default reverts; lock reverts input and restores volume; sub-device
  follows default output. One test file, four tests.
- Manual acceptance on the author's Mac: join a Meet call with Calls selected, play
  music on the real AirPods, confirm loud music, confirm the AirPods output sample
  rate stays at 48 kHz, unplug and replug the AirPods, confirm Calls follows.

## Repository layout

```
calllane/
  Package.swift
  Makefile                # build, bundle, sign, zip
  Sources/CallLane/
    App.swift             # @main, MenuBarExtra
    AudioSystem.swift
    Controller.swift
    MenuView.swift
    SetupView.swift
    Info.plist
  Tests/CallLaneTests/
  .github/workflows/release.yml
  Casks/calllane.rb       # copied into rav4nn/homebrew-tap on release
  README.md
  LICENSE
```

## Known risks stated in the README

- Apple does not document that ducking stops at the aggregate boundary. A macOS
  update can change it.
- The volume keys do nothing when `Calls` is the system default. The app reverts it.
- Spatial Audio and head tracking may not apply to the call on `Calls`. Not verified.
- Safari has no per-site speaker picker, so Meet in Safari cannot use `Calls`.
