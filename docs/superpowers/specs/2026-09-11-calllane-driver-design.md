# CallLane v0.2: driver-backed device

Date: 2026-09-11. Status: approved in chat, supersedes the aggregate design in
`2026-09-11-calllane-design.md` for the device part. Everything not mentioned here
(input lock, menu bar panel, setup guide, cask distribution) stays as designed there.

## Why

WhatsApp for Mac lists only audio devices whose transport type is physical (built-in,
Bluetooth, HDMI, USB, and so on). It hides aggregate devices and devices whose transport
type is "virtual". Verified on macOS 26 with the current WhatsApp for Mac:

| Device | Transport | In WhatsApp picker |
| --- | --- | --- |
| CallLane aggregate | `grup` | no |
| BlackHole 2ch | `virt` | no |
| BlackHole rebuilt to report `usb ` | `usb ` | yes |

A CoreAudio server plugin (a user-space driver in `/Library/Audio/Plug-Ins/HAL`) can
report any transport type. The audio daemon loads such a plugin with an ad-hoc signature.
Call audio sent into a loopback plugin and copied onto the real headphones by the app is
not ducked, the volume keys keep working, and the loudness matches a direct connection.
The only cost is added delay from the copy.

Decisions taken in chat:

1. One device, the plugin, for every app. The aggregate goes away.
2. The driver derives from BlackHole 0.7.1 (commit ffcb744). It ships under GPL-3 with
   credit. The app stays MIT. The repo README states the split.
3. The driver installs through a package inside the cask, not from the app.

## Components

```
call app ──► CallLane (plugin, output only) ──► shared ring in coreaudiod
                                                       │
CallLane.app engine ◄── CallLane Tap (plugin, hidden, input only)
       │
       └──► current default output (AirPods, speakers, ...)
```

### Driver (`Driver/`)

- `Driver/BlackHole.c`: a copy of BlackHole's single source file with a small diff:
  - device 1 output stream reports `kAudioStreamTerminalTypeHeadphones`
  - device transport type reports `kAudioDeviceTransportTypeUSB`
- `Driver/LICENSE`: GPL-3, as in BlackHole. `Driver/NOTICE` names BlackHole, its
  authors, the commit, and the diff.
- Built with `clang -bundle` and the compile-time defines BlackHole already offers:

| Define | Value | Effect |
| --- | --- | --- |
| `kDriver_Name` | `CallLane` | prefix for names and UIDs |
| `kPlugIn_BundleID` | `dev.rav4nn.calllane.driver` | bundle id |
| `kHas_Driver_Name_Format` | `false` | no channel-count suffix |
| `kDevice_Name` | `CallLane` | picker name |
| `kDevice_HasInput` | `false` | device 1 is output only |
| `kDevice2_Name` | `CallLane Tap` | the twin the app reads |
| `kDevice2_HasOutput` | `false` | twin is input only |
| `kDevice2_IsHidden` | `true` | twin never appears in pickers |
| `kEnableVolumeControl` | `false` | no volume control on the device |
| `kNumber_Of_Channels` | `2` | stereo |
| `kLatency_Frame_Size` | `0` | report no latency |

- Device UIDs come from BlackHole's scheme: `CallLane_UID` for the device and
  `CallLane_2_UID` for the twin. These differ from the old aggregate UID
  `dev.rav4nn.calllane.calls` on purpose, so a leftover aggregate can never clash.
- Bundle: `build/CallLane.driver` with `Contents/Info.plist` (from BlackHole's plist
  template with the names filled in) and `Contents/MacOS/CallLane`, signed ad-hoc.
- The driver reports version `CFBundleShortVersionString` equal to the app version. The
  app reads it from the installed bundle's Info.plist.

### Package (`Driver/pkg/`)

- `pkgbuild --component build/CallLane.driver --install-location /Library/Audio/Plug-Ins/HAL --identifier dev.rav4nn.calllane.driver --version <v> --scripts Driver/pkg/scripts build/CallLaneDriver.pkg`
- `Driver/pkg/scripts/postinstall`: `killall coreaudiod` so the driver loads without a
  reboot. Exits 0 even if the daemon was not running.
- Unsigned package. Homebrew runs `installer` with sudo, which accepts it.

### Engine (`Sources/CallLane/Engine.swift`)

One class, `Engine`, that copies audio from the tap device to a destination device.

- Two HAL output units (`kAudioUnitSubType_HALOutput`):
  - input unit: `CurrentDevice` = tap, input enabled, output disabled, input callback
    renders into a preallocated buffer and pushes into the ring
  - output unit: `CurrentDevice` = destination, render callback pops from the ring
- Format: Float32, interleaved, 2 channels, 48000 Hz on both sides. The driver runs at
  48000 Hz. Any destination that cannot do 48000 Hz gets the unit's own converter, which
  the HAL output unit provides when the stream format differs from the device format.
- Buffer sizes: `kAudioDevicePropertyBufferFrameSize` = 128 on both devices.
- Ring: a lock-free single-producer single-consumer ring of 4096 frames. Drift control:
  - on pop, if the ring holds more than 512 frames, drop the oldest frames down to 256
  - on pop, if the ring holds fewer frames than asked, fill the rest with zeros
  Both counts are tunable constants. Added delay target: 10 to 15 ms.
- `start(tap: AudioObjectID, destination: AudioObjectID) throws` and `stop()`. Calling
  `start` while running with a different destination stops and starts again.
- No AVAudioEngine: on macOS it owns one I/O unit for input and output, so it cannot read
  one device and write another.
- Microphone permission (found 2026-09-11 during acceptance): reading the tap is an input
  stream, and macOS feeds an app zeros, with no error, until the user grants microphone
  access. The app declares `NSMicrophoneUsageDescription`, asks at launch, and shows a
  denial in `status`. The "no permission prompts" claim from v0.1 no longer holds.

### Controller changes (`Sources/CallLane/Controller.swift`)

Removed: everything that creates, renames, rewires, or destroys the aggregate.

Kept: input lock, volume slider, default-output listener, in-use detection through
`kAudioDevicePropertyDeviceIsRunningSomewhere` on the plugin device.

New rules in `reconcile()`:

1. Migration: if a device with UID `dev.rav4nn.calllane.calls` exists and is an aggregate,
   destroy it. If it is the default output, move the output to any real output first,
   exactly as the old "leave CallLane" rule did.
2. Driver check: find the plugin device by UID `CallLane_UID` and the tap by
   `CallLane_2_UID`. If either is missing, `status` reads "Driver not installed. Run
   `make install-driver` or reinstall the cask." and the panel shows a "Driver missing"
   row instead of the CallLane status row. Also compare the installed driver's
   `CFBundleShortVersionString` with the app version; when older, `status` reads
   "Driver is v<x>, app is v<y>. Reinstall the cask."
3. CallLane must never be the system output. Unchanged rule, new reason: the engine would
   copy the device into itself.
4. Engine lifecycle: when `callsInUse` becomes true, start the engine with tap and the
   current default output. When it becomes false, stop it. When the default output
   changes while in use, restart the engine with the new destination.
5. The default output can never be the tap device because it has no output streams.

`AudioSystem` gains `bufferFrameSize(_:set:)` only if the engine needs it outside the
units. Otherwise the engine uses the units' own property calls and the protocol is
unchanged apart from removing the aggregate calls.

### Panel and guide

- Status row: "CallLane → <default output>" with the same idle / in use states.
- Footer: "Remove CallLane device and quit" becomes "Quit". Removing the driver is a
  Homebrew uninstall, and the README says so.
- Setup guide: WhatsApp returns to the list: "Settings → Calls → Speaker → CallLane".
  The footnote keeps Safari only.

### Packaging and release

- `make driver` builds the bundle. `make pkg` builds the package. `make install-driver`
  runs the package with `sudo installer -pkg build/CallLaneDriver.pkg -target /`.
- `make release` zips `CallLane.app` and `CallLaneDriver.pkg` into one `CallLane.zip`.
- The workflow builds the driver and runs the unit tests on macos-15.
- Cask:

```ruby
app "CallLane.app"
pkg "CallLaneDriver.pkg"
uninstall pkgutil: "dev.rav4nn.calllane.driver",
          quit:    "dev.rav4nn.calllane",
          script:  { executable: "/usr/bin/killall", args: ["coreaudiod"], sudo: true }
```

- Version v0.2.0. The README install section adds that the package asks for the admin
  password once.

### Licence layout

- `LICENSE` (MIT) covers everything outside `Driver/`.
- `Driver/LICENSE` (GPL-3) covers the driver. `Driver/NOTICE` credits BlackHole by
  Existential Audio, names commit ffcb744, and lists the diff.
- README: one paragraph under a "Licence" heading with both facts.

## Testing

- Controller unit tests keep the fake audio system: migration destroys the old
  aggregate, missing driver sets the status, engine starts on in-use and stops on idle,
  engine restarts on output change. The engine is behind a protocol
  (`EngineControl` with `start`/`stop`) so the fake records calls.
- Engine live test (`Tests/CallLaneTests/EngineTests.swift`): needs the driver
  installed. It sets the system output to CallLane, plays a short generated tone through
  the default output unit, reads the tap through the engine into the MacBook speakers at
  volume zero, and asserts the ring saw a peak above 0.1. Skipped when the driver is
  absent. Not run in CI.
- Driver: CI compiles it. Manual check after install: `system_profiler SPAudioDataType`
  lists "CallLane" with Transport USB and no "CallLane Tap".
- Manual acceptance on this Mac: WhatsApp, Meet, and FaceTime calls with speaker =
  CallLane, media stays loud, delay not noticeable, volume keys work, AirPods stay at
  48 kHz.

## Out of scope

- A Developer ID signature or notarisation.
- Per-app volume, or mirroring the AirPods volume onto the device.
- Sample rates other than 48 kHz on the device.
- Removing the driver from inside the app.
