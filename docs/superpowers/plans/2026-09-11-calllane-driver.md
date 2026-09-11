# CallLane v0.2 Driver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the CoreAudio aggregate device with a driver-backed `CallLane` device that WhatsApp can select, and copy its audio onto the real headphones from the app.

**Architecture:** A HAL server plugin derived from BlackHole exposes two devices: `CallLane` (output only, transport USB) and a hidden `CallLane Tap` (input only). Both share one ring inside coreaudiod. The app's new `Engine` reads the tap with one HAL output unit and writes the current default output with a second one, joined by a small ring buffer. `Controller.reconcile()` loses every aggregate rule and gains four new ones: migrate the old aggregate away, report a missing or old driver, keep `CallLane` off the system output, and start or stop the engine as call apps come and go.

**Tech Stack:** Swift 5.9, SwiftUI `MenuBarExtra`, CoreAudio HAL C API, AudioToolbox HAL output units (`kAudioUnitSubType_HALOutput`), a C plugin built with `clang -bundle`, `pkgbuild`, Swift Testing, GitHub Actions on macos-15, Homebrew cask.

**Spec:** `docs/superpowers/specs/2026-09-11-calllane-driver-design.md`. Everything the spec does not change stays as in `docs/superpowers/specs/2026-09-11-calllane-design.md`.

## Global Constraints

- Minimum macOS: 14. `Package.swift` platforms `[.macOS(.v14)]`. Info.plist `LSMinimumSystemVersion` `14.0`.
- No third-party dependencies. No Xcode project. Build with `swift build`, `clang`, and the Makefile. The Xcode Command Line Tools are the only toolchain.
- App bundle identifier `dev.rav4nn.calllane`. Driver bundle identifier `dev.rav4nn.calllane.driver`. Package identifier `dev.rav4nn.calllane.driver`.
- Device name exactly `CallLane`, UID exactly `CallLane_UID`. Tap name exactly `CallLane Tap`, UID exactly `CallLane_2_UID`. Old aggregate UID `dev.rav4nn.calllane.calls` is read for migration only.
- Driver defines, verbatim from the spec: `kDriver_Name` `CallLane`, `kPlugIn_BundleID` `dev.rav4nn.calllane.driver`, `kHas_Driver_Name_Format` `false`, `kDevice_Name` `CallLane`, `kDevice_HasInput` `false`, `kDevice2_Name` `CallLane Tap`, `kDevice2_HasOutput` `false`, `kDevice2_IsHidden` `true`, `kEnableVolumeControl` `false`, `kNumber_Of_Channels` `2`, `kLatency_Frame_Size` `0`. Plus `kSampleRates` `48000` so the device runs at 48 kHz only (spec: "The driver runs at 48000 Hz").
- Driver derives from BlackHole 0.7.1 commit `ffcb744`. `Driver/` is GPL-3 with a NOTICE crediting BlackHole. Everything else stays MIT, copyright holder "Hardeep Singh".
- Driver installs from `CallLaneDriver.pkg` inside the cask. The app never installs or removes the driver.
- Engine: Float32 interleaved stereo 48 kHz, 128-frame device buffers, ring of 4096 frames, drop above 512 frames down to 256, zero-fill on underrun.
- Version v0.2.0. The driver's `CFBundleShortVersionString` equals the app version.
- Commits under ~/work pass the Codex pre-commit gate: run the Codex review per the `codex-review-protocol` skill, apply the good fixes, run `codex-receipt`, then commit. `CODEX_SKIP_REVIEW=1` is allowed only where a task says so.
- Never `git push`, tag on the remote, or open a PR. The user runs `lgtm` and pushes.
- Every `sudo` step runs in the user's terminal. The plan prints the command and waits.
- `make test` passes the Swift Testing plugin path for the Command Line Tools. Run tests through `make test`, not bare `swift test`.

---

### Task 1: Vendor the driver source and build the bundle

**Files:**
- Create: `Driver/BlackHole.c` (copy of BlackHole's file with a three-line patch)
- Create: `Driver/LICENSE` (GPL-3 text)
- Create: `Driver/NOTICE`
- Create: `Driver/Info.plist`
- Modify: `Makefile`

**Interfaces:**
- Produces: `make driver` writes `build/CallLane.driver`, ad-hoc signed. `VERSION` Makefile variable read from `Sources/CallLane/Info.plist`.

- [ ] **Step 1: Get the BlackHole source at commit ffcb744**

A patched clone may still exist in the previous session's scratchpad. Check first:

```bash
SP=/private/tmp/claude-501/-Users-rav4nn/8b91ad59-a472-46bc-a023-a11f4165423e/scratchpad
ls "$SP/BlackHole/BlackHole/BlackHole.c" && git -C "$SP/BlackHole" diff --stat
```

If it exists and the diff shows `BlackHole/BlackHole.c | 6 +++---`, use it:

```bash
cd /Users/rav4nn/work/projects/calllane
mkdir -p Driver
cp "$SP/BlackHole/BlackHole/BlackHole.c" Driver/BlackHole.c
sed -n '/GNU GENERAL PUBLIC LICENSE/,$p' "$SP/BlackHole/LICENSE" > Driver/LICENSE
```

If the scratchpad is gone, clone and patch by hand:

```bash
cd /private/tmp/claude-501/-Users-rav4nn/712c4b71-f21a-4c71-b003-ae7cc1135d93/scratchpad
git clone https://github.com/ExistentialAudio/BlackHole && git -C BlackHole checkout ffcb744
cd /Users/rav4nn/work/projects/calllane
mkdir -p Driver
cp /private/tmp/claude-501/-Users-rav4nn/712c4b71-f21a-4c71-b003-ae7cc1135d93/scratchpad/BlackHole/BlackHole/BlackHole.c Driver/BlackHole.c
sed -n '/GNU GENERAL PUBLIC LICENSE/,$p' /private/tmp/claude-501/-Users-rav4nn/712c4b71-f21a-4c71-b003-ae7cc1135d93/scratchpad/BlackHole/LICENSE > Driver/LICENSE
```

Then apply the patch. There are exactly three lines to change in `Driver/BlackHole.c`; each original line appears once in the file:

```bash
cd /Users/rav4nn/work/projects/calllane
# Box transport (inside BlackHole_GetBoxPropertyData) and device transport (inside
# BlackHole_GetDevicePropertyData) both read kAudioDeviceTransportTypeVirtual.
sed -i '' 's/\*((UInt32\*)outData) = kAudioDeviceTransportTypeVirtual;/*((UInt32*)outData) = kAudioDeviceTransportTypeUSB;/' Driver/BlackHole.c
# Output stream terminal type.
sed -i '' 's/kAudioStreamTerminalTypeMicrophone : kAudioStreamTerminalTypeSpeaker;/kAudioStreamTerminalTypeMicrophone : kAudioStreamTerminalTypeHeadphones;/' Driver/BlackHole.c
grep -c "kAudioDeviceTransportTypeUSB;" Driver/BlackHole.c    # expect 2
grep -c "kAudioStreamTerminalTypeHeadphones;" Driver/BlackHole.c   # expect 1
grep -c "kAudioDeviceTransportTypeVirtual;" Driver/BlackHole.c   # expect 0
```

Expected: the three counts are 2, 1, 0. The first line of `Driver/LICENSE` is `                    GNU GENERAL PUBLIC LICENSE`.

- [ ] **Step 2: Write Driver/NOTICE**

```text
CallLane driver
===============

This folder is a derivative of BlackHole by Existential Audio Inc.
https://github.com/ExistentialAudio/BlackHole, version 0.7.1, commit ffcb744.
BlackHole is (c) 2019-2026 Existential Audio Inc. and is licensed under the
GNU General Public License v3.0. The full licence text is in LICENSE in this
folder. This folder is distributed under the same licence.

Changes to BlackHole/BlackHole.c:

1. The box and the device report transport type USB instead of Virtual, so
   call apps that list only physical devices (WhatsApp for Mac) show the device.
2. The output stream reports terminal type Headphones instead of Speaker.

Everything else is set through BlackHole's compile-time defines; see the
`driver` target in the Makefile at the repository root.

The rest of CallLane, everything outside this folder, is (c) 2026 Hardeep Singh
and is licensed under the MIT License (see LICENSE at the repository root).
```

- [ ] **Step 3: Write Driver/Info.plist**

This is BlackHole's plist template with the names filled in. `@VERSION@` is replaced by the Makefile. The two UUIDs must stay as they are: the second one is the AudioServerPlugIn type, the first one names the factory `BlackHole_Create` inside the C file.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>English</string>
    <key>CFBundleExecutable</key><string>CallLane</string>
    <key>CFBundleIdentifier</key><string>dev.rav4nn.calllane.driver</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>CallLane</string>
    <key>CFBundlePackageType</key><string>BNDL</string>
    <key>CFBundleShortVersionString</key><string>@VERSION@</string>
    <key>CFBundleSignature</key><string>????</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>NSHumanReadableCopyright</key><string>Derived from BlackHole, © Existential Audio Inc. GPL-3.</string>
    <key>CFPlugInFactories</key>
    <dict>
        <key>e395c745-4eea-4d94-bb92-46224221047c</key><string>BlackHole_Create</string>
    </dict>
    <key>CFPlugInTypes</key>
    <dict>
        <key>443ABAB8-E7B3-491A-B985-BEB9187030DB</key>
        <array><string>e395c745-4eea-4d94-bb92-46224221047c</string></array>
    </dict>
</dict>
</plist>
```

- [ ] **Step 4: Add the `driver` target to the Makefile**

Replace the top of `Makefile` (the four variable lines and the `.PHONY` line) with this block. Keep every existing target below it unchanged.

```make
APP     = CallLane
BUILD   = build
BUNDLE  = $(BUILD)/$(APP).app
BIN     = .build/release/$(APP)
VERSION = $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Sources/$(APP)/Info.plist)

DRIVER  = $(BUILD)/$(APP).driver
# The device the call apps pick is output only; its hidden twin is the input the app reads.
# Both share one ring inside coreaudiod. 48 kHz only: the engine assumes it.
DRIVER_DEFINES = \
	-DkDriver_Name='"$(APP)"' \
	-DkPlugIn_BundleID='"dev.rav4nn.calllane.driver"' \
	-DkHas_Driver_Name_Format=false \
	-DkDevice_Name='"$(APP)"' \
	-DkDevice_HasInput=false \
	-DkDevice2_Name='"$(APP) Tap"' \
	-DkDevice2_HasOutput=false \
	-DkDevice2_IsHidden=true \
	-DkEnableVolumeControl=false \
	-DkManufacturer_Name='"$(APP)"' \
	-DkNumber_Of_Channels=2 \
	-DkLatency_Frame_Size=0 \
	-DkSampleRates=48000

.PHONY: build run test driver release snap clean

driver:
	rm -rf $(DRIVER)
	mkdir -p $(DRIVER)/Contents/MacOS
	clang -bundle -O2 -framework CoreAudio -framework CoreFoundation -framework Accelerate \
		$(DRIVER_DEFINES) -o $(DRIVER)/Contents/MacOS/$(APP) Driver/BlackHole.c
	sed 's/@VERSION@/$(VERSION)/' Driver/Info.plist > $(DRIVER)/Contents/Info.plist
	codesign --force --sign - $(DRIVER)
```

- [ ] **Step 5: Build and inspect the bundle**

```bash
cd /Users/rav4nn/work/projects/calllane
make driver 2>&1 | tail -5
codesign -dv build/CallLane.driver 2>&1 | grep -E "Identifier|Signature"
/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/CallLane.driver/Contents/Info.plist
strings build/CallLane.driver/Contents/MacOS/CallLane | grep -E "^CallLane(_2)?_UID$|^CallLane Tap$"
```

Expected: `Identifier=dev.rav4nn.calllane.driver`, `Signature=adhoc`, version `0.1.0` (the bump comes in Task 7), and the three strings `CallLane_UID`, `CallLane_2_UID`, `CallLane Tap`. Warnings from clang about BlackHole's code are fine; errors are not.

- [ ] **Step 6: Commit**

The C file is vendored and the Makefile target has no logic. `CODEX_SKIP_REVIEW=1` is allowed for this commit.

```bash
cd /Users/rav4nn/work/projects/calllane
git add Driver Makefile
CODEX_SKIP_REVIEW=1 git commit -m "driver: vendor BlackHole ffcb744 as the CallLane HAL plugin (USB transport, Headphones)"
```

---

### Task 2: Package, install target, and first install on this Mac

**Files:**
- Create: `Driver/pkg/scripts/postinstall`
- Modify: `Makefile`

**Interfaces:**
- Produces: `make pkg` writes `build/CallLaneDriver.pkg`. `make install-driver` installs it (asks for sudo). After install, `/Library/Audio/Plug-Ins/HAL/CallLane.driver/Contents/Info.plist` exists and `system_profiler` lists `CallLane` with transport USB.

- [ ] **Step 1: Write the postinstall script**

```sh
#!/bin/sh
# Restart the audio daemon so the new driver loads without a reboot.
# coreaudiod is always running on a live system; exit 0 either way.
killall coreaudiod 2>/dev/null || true
exit 0
```

Then:

```bash
chmod +x /Users/rav4nn/work/projects/calllane/Driver/pkg/scripts/postinstall
```

`pkgbuild` refuses a scripts folder whose files are not executable.

- [ ] **Step 2: Add `pkg` and `install-driver` targets**

Add after the `driver` target in `Makefile`, and add `pkg install-driver` to the `.PHONY` line:

```make
PKG     = $(BUILD)/$(APP)Driver.pkg
HAL_DIR = /Library/Audio/Plug-Ins/HAL

pkg: driver
	pkgbuild --component $(DRIVER) --install-location $(HAL_DIR) \
		--identifier dev.rav4nn.calllane.driver --version $(VERSION) \
		--scripts Driver/pkg/scripts $(PKG)

install-driver: pkg
	sudo installer -pkg $(PKG) -target /
```

- [ ] **Step 3: Build the package and check its payload**

```bash
cd /Users/rav4nn/work/projects/calllane
make pkg 2>&1 | tail -3
pkgutil --payload-files build/CallLaneDriver.pkg
```

Expected: `pkgbuild: Wrote package to build/CallLaneDriver.pkg` and a payload of `./CallLane.driver`, `./CallLane.driver/Contents`, `./CallLane.driver/Contents/Info.plist`, `./CallLane.driver/Contents/MacOS`, `./CallLane.driver/Contents/MacOS/CallLane`, plus `_CodeSignature` entries.

- [ ] **Step 4: Ask the user to remove the two test plugins and the throwaway passthrough**

Print this and wait. These commands need the user's password. The throwaway passthrough feeds the user's current WhatsApp calls, so ask them to run it between calls.

```bash
pkill -x passthru3
sudo rm -rf /Library/Audio/Plug-Ins/HAL/CallLaneTest.driver /Library/Audio/Plug-Ins/HAL/CallLaneTest2.driver
sudo killall coreaudiod
```

Confirm afterwards:

```bash
ls /Library/Audio/Plug-Ins/HAL/
```

Expected: no `CallLaneTest.driver` and no `CallLaneTest2.driver`. `BlackHole2ch.driver` may stay; its removal is the user's call (`brew uninstall --cask blackhole-2ch`).

- [ ] **Step 5: Ask the user to install the driver**

Print this and wait:

```bash
cd /Users/rav4nn/work/projects/calllane && make install-driver
```

- [ ] **Step 6: Verify the installed driver**

```bash
system_profiler SPAudioDataType | grep -B1 -A8 "CallLane"
ls /Library/Audio/Plug-Ins/HAL/CallLane.driver/Contents/MacOS/
```

Expected: one block headed `CallLane:` with `Transport: USB`, `Manufacturer: CallLane`, an `Output Channels: 2` line and no `Input Channels` line. No block headed `CallLane Tap`. If nothing appears, ask the user to run `sudo killall coreaudiod` once more; the previous session saw one load fail on the first restart.

- [ ] **Step 7: Commit**

No logic in this task. `CODEX_SKIP_REVIEW=1` is allowed.

```bash
cd /Users/rav4nn/work/projects/calllane
git add Driver/pkg Makefile
CODEX_SKIP_REVIEW=1 git commit -m "driver: package and install targets"
```

---

### Task 3: AudioSystem learns to find a device by UID and to read the driver version

**Files:**
- Modify: `Sources/CallLane/AudioSystem.swift`
- Modify: `Tests/CallLaneTests/FakeAudioSystem.swift`
- Test: `Tests/CallLaneTests/AudioSystemTests.swift`

**Interfaces:**
- Produces on `protocol AudioSystem`: `func deviceID(forUID uid: String) -> AudioObjectID?` and `func driverVersion() -> String?`.
- Produces on `CoreAudioSystem`: `init(driverPlist: String = CoreAudioSystem.driverPlist)` and `static let driverPlist = "/Library/Audio/Plug-Ins/HAL/CallLane.driver/Contents/Info.plist"`.
- Produces on `FakeAudioSystem`: `var installedDriverVersion: String? = "0.2.0"`.

- [ ] **Step 1: Write the failing tests**

Replace the whole of `Tests/CallLaneTests/AudioSystemTests.swift` with:

```swift
import Testing
import Foundation
@testable import CallLane

@Suite struct AudioSystemTests {
    let uid = "dev.rav4nn.calllane.test-\(ProcessInfo.processInfo.processIdentifier)"

    @Test func aggregateLifecycle() throws {
        let audio = CoreAudioSystem()
        guard let out = audio.defaultOutput(),
              let outDevice = audio.devices().first(where: { $0.id == out }) else {
            Issue.record("no default output device on this Mac"); return
        }
        let agg = try audio.createAggregate(name: "CallLane Test", uid: uid, subDeviceUID: outDevice.uid)
        defer { try? audio.destroyAggregate(agg) }

        #expect(audio.deviceID(forUID: uid) == agg)
        #expect(audio.deviceID(forUID: "dev.rav4nn.calllane.no-such-device") == nil)
        #expect(audio.volume(agg, scope: .output) == nil, "aggregates have no volume control")
        #expect(audio.devices().contains { $0.uid == uid && $0.isAggregate })
        #expect(!audio.isRunningSomewhere(agg))
    }

    @Test func defaultDevicesResolve() {
        let audio = CoreAudioSystem()
        let ids = Set(audio.devices().map(\.id))
        if let o = audio.defaultOutput() { #expect(ids.contains(o)) }
        if let i = audio.defaultInput() { #expect(ids.contains(i)) }
    }

    @Test func driverVersionReadsTheInstalledPlist() throws {
        let plist = FileManager.default.temporaryDirectory.appendingPathComponent("calllane-\(uid).plist")
        defer { try? FileManager.default.removeItem(at: plist) }
        try (["CFBundleShortVersionString": "1.2.3"] as NSDictionary).write(to: plist)
        #expect(CoreAudioSystem(driverPlist: plist.path).driverVersion() == "1.2.3")
        #expect(CoreAudioSystem(driverPlist: "/nonexistent/Info.plist").driverVersion() == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd /Users/rav4nn/work/projects/calllane && make test 2>&1 | tail -15`
Expected: compile errors, `value of type 'CoreAudioSystem' has no member 'deviceID'` and `extra argument 'driverPlist' in call`.

- [ ] **Step 3: Add the two functions**

In `Sources/CallLane/AudioSystem.swift`, add to `protocol AudioSystem` after `func isRunningSomewhere(_ id: AudioObjectID) -> Bool`:

```swift
    /// Resolves a device UID; nil when no device has it. Finds hidden devices too.
    func deviceID(forUID uid: String) -> AudioObjectID?
    /// `CFBundleShortVersionString` of the installed CallLane driver; nil when not installed.
    func driverVersion() -> String?
```

In `final class CoreAudioSystem`, replace the first line `private let system = AudioObjectID(kAudioObjectSystemObject)` with:

```swift
    static let driverPlist = "/Library/Audio/Plug-Ins/HAL/CallLane.driver/Contents/Info.plist"

    private let system = AudioObjectID(kAudioObjectSystemObject)
    private let driverPlist: String

    init(driverPlist: String = CoreAudioSystem.driverPlist) {
        self.driverPlist = driverPlist
    }
```

Add after `func isRunningSomewhere`:

```swift
    func deviceID(forUID uid: String) -> AudioObjectID? {
        var a = address(kAudioHardwarePropertyTranslateUIDToDevice)
        var cf = uid as CFString
        var id: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &cf) {
            AudioObjectGetPropertyData(system, &a, UInt32(MemoryLayout<CFString>.size), $0, &size, &id)
        }
        // An unknown UID answers noErr with kAudioObjectUnknown (0).
        return status == noErr && id != 0 ? id : nil
    }

    func driverVersion() -> String? {
        NSDictionary(contentsOfFile: driverPlist)?["CFBundleShortVersionString"] as? String
    }
```

In `Tests/CallLaneTests/FakeAudioSystem.swift`, add the property after `var failSetDefaultInput = false`:

```swift
    var installedDriverVersion: String? = "0.2.0"
```

and the two functions after `func isRunningSomewhere`:

```swift
    func deviceID(forUID uid: String) -> AudioObjectID? { list.first { $0.uid == uid }?.id }
    func driverVersion() -> String? { installedDriverVersion }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd /Users/rav4nn/work/projects/calllane && make test 2>&1 | tail -15`
Expected: every suite passes, including `driverVersionReadsTheInstalledPlist` and `aggregateLifecycle`.

- [ ] **Step 5: Review and commit**

Run the Codex review per the `codex-review-protocol` skill, apply the good fixes, re-run `make test`, run `codex-receipt`, then:

```bash
cd /Users/rav4nn/work/projects/calllane
git add Sources/CallLane/AudioSystem.swift Tests/CallLaneTests
git commit -m "audio: resolve devices by UID and read the installed driver version"
```

---

### Task 4: Engine — ring buffer and the two-unit passthrough

**Files:**
- Create: `Sources/CallLane/Engine.swift`
- Test: `Tests/CallLaneTests/RingTests.swift`
- Test: `Tests/CallLaneTests/EngineTests.swift`

**Interfaces:**
- Consumes: `AudioError` from `AudioSystem.swift`; `CoreAudioSystem.deviceID(forUID:)` and `CoreAudioSystem.driverPlist` from Task 3.
- Produces: `protocol EngineControl: AnyObject { func start(tap: AudioObjectID, destination: AudioObjectID) throws; func stop() }`, `final class Engine: EngineControl` with `static let format: AudioStreamBasicDescription`, `let ring: Ring`, `private(set) var current: (tap: AudioObjectID, destination: AudioObjectID)?`. `final class Ring` with `init(capacity: Int = 4096, dropAbove: Int = 512, dropTo: Int = 256)`, `func push(_ p: UnsafePointer<Float>, frames: Int)`, `@discardableResult func pop(into p: UnsafeMutablePointer<Float>, frames: Int) -> Int`, `var available: Int`, `private(set) var peak: Float`, `func reset()`.
- Task 5 uses the UID constants `Controller.callsUID` and `Controller.tapUID`; the live test here spells the strings out because Task 5 has not run yet.

- [ ] **Step 1: Write the failing ring tests**

`Tests/CallLaneTests/RingTests.swift`:

```swift
import Testing
@testable import CallLane

/// Frames are interleaved stereo; each helper frame carries its index in both channels.
@Suite struct RingTests {
    func frames(_ range: Range<Int>) -> [Float] { range.flatMap { [Float($0), Float($0)] } }

    @Test func popReturnsOldestFirstAndZeroFillsTheRest() {
        let ring = Ring(capacity: 16, dropAbove: 8, dropTo: 4)
        var input = frames(0..<3)
        ring.push(&input, frames: 3)
        var out = [Float](repeating: 9, count: 8)
        #expect(ring.pop(into: &out, frames: 4) == 3)
        #expect(out == [0, 0, 1, 1, 2, 2, 0, 0])
        #expect(ring.available == 0)
    }

    @Test func popDropsBacklogAboveThreshold() {
        let ring = Ring(capacity: 16, dropAbove: 8, dropTo: 4)
        var input = frames(0..<10)
        ring.push(&input, frames: 10)          // 10 > 8: the next pop keeps only the newest 4
        var out = [Float](repeating: 9, count: 4)
        #expect(ring.pop(into: &out, frames: 2) == 2)
        #expect(out == [6, 6, 7, 7])
        #expect(ring.available == 2)
    }

    @Test func pushOverwritesOldestWhenFull() {
        let ring = Ring(capacity: 4, dropAbove: 100, dropTo: 100)
        var input = frames(0..<6)
        ring.push(&input, frames: 6)
        #expect(ring.available == 4)
        var out = [Float](repeating: 9, count: 8)
        #expect(ring.pop(into: &out, frames: 4) == 4)
        #expect(out == [2, 2, 3, 3, 4, 4, 5, 5])
    }

    @Test func peakTracksTheLoudestSampleUntilReset() {
        let ring = Ring()
        var input: [Float] = [0.1, -0.7, 0.2, 0.0]
        ring.push(&input, frames: 2)
        #expect(ring.peak == 0.7)
        ring.reset()
        #expect(ring.peak == 0)
        #expect(ring.available == 0)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd /Users/rav4nn/work/projects/calllane && make test 2>&1 | tail -8`
Expected: `cannot find 'Ring' in scope`.

- [ ] **Step 3: Write Engine.swift**

```swift
import AudioToolbox
import CoreAudio
import Foundation

protocol EngineControl: AnyObject {
    /// Copies `tap` onto `destination`. A second call with the same pair is a no-op; a
    /// different pair stops the current copy first.
    func start(tap: AudioObjectID, destination: AudioObjectID) throws
    func stop()
}

/// Single-producer single-consumer ring of interleaved stereo Float32 frames.
/// The producer is the tap's input callback, the consumer the destination's render callback.
/// ponytail: NSLock around a copy of at most 512 floats; a lock-free ring needs the
/// Synchronization module (macOS 15) or a C atomics shim. Upgrade if a glitch is ever traced here.
final class Ring {
    let capacity: Int
    let dropAbove: Int
    let dropTo: Int
    private let buf: UnsafeMutablePointer<Float>
    private let lock = NSLock()
    private var head = 0     // next frame to write
    private var count = 0    // frames waiting to be read
    private(set) var peak: Float = 0

    init(capacity: Int = 4096, dropAbove: Int = 512, dropTo: Int = 256) {
        self.capacity = capacity
        self.dropAbove = dropAbove
        self.dropTo = dropTo
        buf = .allocate(capacity: capacity * 2)
        buf.initialize(repeating: 0, count: capacity * 2)
    }

    deinit { buf.deallocate() }

    var available: Int { lock.lock(); defer { lock.unlock() }; return count }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        head = 0; count = 0; peak = 0
    }

    /// Appends frames. When the ring is full the oldest frames are overwritten.
    func push(_ p: UnsafePointer<Float>, frames: Int) {
        lock.lock(); defer { lock.unlock() }
        for i in 0..<frames {
            let f = (head + i) % capacity
            buf[f * 2] = p[i * 2]
            buf[f * 2 + 1] = p[i * 2 + 1]
            peak = max(peak, abs(p[i * 2]), abs(p[i * 2 + 1]))
        }
        head = (head + frames) % capacity
        count = min(capacity, count + frames)
    }

    /// Fills `frames` frames: the oldest waiting frames first, zeros for the rest.
    /// A backlog above `dropAbove` is cut to `dropTo` first, so the added delay stays bounded.
    /// Returns the number of real frames written.
    @discardableResult
    func pop(into p: UnsafeMutablePointer<Float>, frames: Int) -> Int {
        lock.lock(); defer { lock.unlock() }
        if count > dropAbove { count = dropTo }
        let got = min(count, frames)
        var tail = (head - count + capacity) % capacity
        for i in 0..<got {
            p[i * 2] = buf[tail * 2]
            p[i * 2 + 1] = buf[tail * 2 + 1]
            tail = (tail + 1) % capacity
        }
        for i in got..<frames {
            p[i * 2] = 0
            p[i * 2 + 1] = 0
        }
        count -= got
        return got
    }
}

/// Copies audio from the hidden CallLane tap device onto the real output.
/// Two HAL output units: the input unit reads the tap, the output unit writes the destination.
/// AVAudioEngine cannot do this on macOS: it owns one I/O unit for both directions.
final class Engine: EngineControl {
    static let bufferFrames: UInt32 = 128
    static let maxFrames = 4096
    static let format = AudioStreamBasicDescription(
        mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
        mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)

    let ring = Ring()
    private(set) var current: (tap: AudioObjectID, destination: AudioObjectID)?
    private var inUnit: AudioUnit?
    private var outUnit: AudioUnit?
    private let inBuf = UnsafeMutablePointer<Float>.allocate(capacity: Engine.maxFrames * 2)

    deinit {
        stop()
        inBuf.deallocate()
    }

    func start(tap: AudioObjectID, destination: AudioObjectID) throws {
        if let c = current {
            if c.tap == tap && c.destination == destination { return }
            stop()
        }
        let input = try makeUnit()
        let output = try makeUnit()
        inUnit = input
        outUnit = output
        do {
            var on: UInt32 = 1, off: UInt32 = 0
            var tapID = tap, dstID = destination
            var frames = Self.bufferFrames
            var format = Self.format
            let fmtSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            let cbSize = UInt32(MemoryLayout<AURenderCallbackStruct>.size)
            let me = Unmanaged.passUnretained(self).toOpaque()

            try check(AudioUnitSetProperty(input, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on, 4), "enable tap input")
            try check(AudioUnitSetProperty(input, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &off, 4), "disable tap output")
            try check(AudioUnitSetProperty(input, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &tapID, 4), "select tap")
            try check(AudioUnitSetProperty(input, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &format, fmtSize), "tap format")
            try check(AudioUnitSetProperty(input, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &frames, 4), "tap buffer size")
            var inCB = AURenderCallbackStruct(inputProc: engineCapture, inputProcRefCon: me)
            try check(AudioUnitSetProperty(input, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &inCB, cbSize), "tap callback")

            try check(AudioUnitSetProperty(output, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dstID, 4), "select output")
            try check(AudioUnitSetProperty(output, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, fmtSize), "output format")
            try check(AudioUnitSetProperty(output, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &frames, 4), "output buffer size")
            var outCB = AURenderCallbackStruct(inputProc: engineRender, inputProcRefCon: me)
            try check(AudioUnitSetProperty(output, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &outCB, cbSize), "output callback")

            try check(AudioUnitInitialize(input), "initialise tap unit")
            try check(AudioUnitInitialize(output), "initialise output unit")
            ring.reset()
            try check(AudioOutputUnitStart(output), "start output")
            try check(AudioOutputUnitStart(input), "start tap")
        } catch {
            stop()
            throw error
        }
        current = (tap, destination)
        log.info("engine: \(tap) -> \(destination)")
    }

    func stop() {
        for unit in [inUnit, outUnit].compactMap({ $0 }) {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
        inUnit = nil
        outUnit = nil
        if current != nil { log.info("engine: stopped") }
        current = nil
    }

    // MARK: callbacks (IO thread)

    fileprivate func capture(_ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, _ time: UnsafePointer<AudioTimeStamp>, _ bus: UInt32, _ frames: UInt32) -> OSStatus {
        guard let unit = inUnit, frames <= Self.maxFrames else { return noErr }
        var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: frames * 8, mData: inBuf))
        let status = AudioUnitRender(unit, flags, time, bus, frames, &list)
        if status == noErr { ring.push(inBuf, frames: Int(frames)) }
        return status
    }

    fileprivate func render(_ io: UnsafeMutablePointer<AudioBufferList>?, _ frames: UInt32) -> OSStatus {
        guard let data = io?.pointee.mBuffers.mData else { return noErr }
        ring.pop(into: data.assumingMemoryBound(to: Float.self), frames: Int(frames))
        return noErr
    }

    // MARK: helpers

    private func makeUnit() throws -> AudioUnit {
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
                                             componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &desc) else {
            throw AudioError(what: "find HAL output unit", status: kAudioUnitErr_InvalidElement)
        }
        var unit: AudioUnit?
        try check(AudioComponentInstanceNew(component, &unit), "create HAL output unit")
        return unit!
    }

    private func check(_ status: OSStatus, _ what: String) throws {
        if status != noErr { throw AudioError(what: what, status: status) }
    }
}

// C function pointers cannot capture; the engine travels through the refCon.
private func engineCapture(_ ref: UnsafeMutableRawPointer, _ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                           _ time: UnsafePointer<AudioTimeStamp>, _ bus: UInt32, _ frames: UInt32,
                           _: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    Unmanaged<Engine>.fromOpaque(ref).takeUnretainedValue().capture(flags, time, bus, frames)
}

private func engineRender(_ ref: UnsafeMutableRawPointer, _: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                          _: UnsafePointer<AudioTimeStamp>, _: UInt32, _ frames: UInt32,
                          _ io: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    Unmanaged<Engine>.fromOpaque(ref).takeUnretainedValue().render(io, frames)
}
```

- [ ] **Step 4: Run the ring tests to verify they pass**

Run: `cd /Users/rav4nn/work/projects/calllane && make test 2>&1 | tail -10`
Expected: `RingTests` passes all four tests.

- [ ] **Step 5: Write the live engine test**

`Tests/CallLaneTests/EngineTests.swift`. It runs only when the driver is installed (the `.enabled(if:)` trait reads the plist path), so CI skips it on its own.

```swift
import Testing
import AudioToolbox
import CoreAudio
import Foundation
@testable import CallLane

/// Needs the CallLane driver (`make install-driver`). Plays a tone into CallLane, copies the tap
/// onto the built-in speakers at volume zero, and checks that audio arrived.
@Suite(.enabled(if: FileManager.default.fileExists(atPath: CoreAudioSystem.driverPlist)))
struct EngineTests {
    @Test func copiesTapOntoDestination() throws {
        let audio = CoreAudioSystem()
        let calls = try #require(audio.deviceID(forUID: "CallLane_UID"))
        let tap = try #require(audio.deviceID(forUID: "CallLane_2_UID"))
        let speakers = try #require(audio.devices().first { $0.transport == kAudioDeviceTransportTypeBuiltIn && $0.hasOutput })

        let savedVolume = audio.volume(speakers.id, scope: .output)
        try audio.setVolume(speakers.id, scope: .output, 0)
        defer { if let v = savedVolume { try? audio.setVolume(speakers.id, scope: .output, v) } }

        let tone = try Tone(device: calls)
        defer { tone.stop() }
        let engine = Engine()
        defer { engine.stop() }

        try engine.start(tap: tap, destination: speakers.id)
        #expect(engine.current?.destination == speakers.id)
        Thread.sleep(forTimeInterval: 0.5)
        #expect(engine.ring.peak > 0.1, "the tap delivered the tone")

        try engine.start(tap: tap, destination: speakers.id)   // same pair: no restart
        #expect(engine.current != nil)
        engine.stop()
        #expect(engine.current == nil)
    }
}

/// Plays a 440 Hz sine at half scale into one output device. Test support only.
final class Tone {
    private var unit: AudioUnit?
    fileprivate var phase: Float = 0

    init(device: AudioObjectID) throws {
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
                                             componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        var made: AudioUnit?
        AudioComponentInstanceNew(AudioComponentFindNext(nil, &desc)!, &made)
        let unit = try #require(made)
        self.unit = unit
        var dev = device
        var format = Engine.format
        AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dev, 4)
        AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        var cb = AURenderCallbackStruct(inputProc: toneRender, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cb, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        let initStatus = AudioUnitInitialize(unit)
        #expect(initStatus == noErr)
        let startStatus = AudioOutputUnitStart(unit)
        #expect(startStatus == noErr)
    }

    func stop() {
        if let u = unit { AudioOutputUnitStop(u); AudioUnitUninitialize(u); AudioComponentInstanceDispose(u) }
        unit = nil
    }
}

private func toneRender(_ ref: UnsafeMutableRawPointer, _: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                        _: UnsafePointer<AudioTimeStamp>, _: UInt32, _ frames: UInt32,
                        _ io: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    let tone = Unmanaged<Tone>.fromOpaque(ref).takeUnretainedValue()
    guard let p = io?.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
    for i in 0..<Int(frames) {
        let v = 0.5 * sin(tone.phase)
        p[i * 2] = v
        p[i * 2 + 1] = v
        tone.phase += 2 * .pi * 440 / 48000
    }
    return noErr
}
```

- [ ] **Step 6: Run the live test**

Run: `cd /Users/rav4nn/work/projects/calllane && make test 2>&1 | grep -E "EngineTests|copiesTap|passed|failed"`
Expected: `copiesTapOntoDestination` passes. If `peak` stays 0, the tap is not receiving the tone: check `system_profiler SPAudioDataType` shows `CallLane`, and that no other process holds the tap. If `select tap failed`, the hidden device id is stale after a `coreaudiod` restart; re-run.

- [ ] **Step 7: Review and commit**

Run the Codex review per the `codex-review-protocol` skill, apply the good fixes, re-run `make test`, run `codex-receipt`, then:

```bash
cd /Users/rav4nn/work/projects/calllane
git add Sources/CallLane/Engine.swift Tests/CallLaneTests/RingTests.swift Tests/CallLaneTests/EngineTests.swift
git commit -m "engine: copy the CallLane tap onto the real output through two HAL units"
```

---

### Task 5: Controller — drop the aggregate, add migration, driver check, and engine lifecycle

**Files:**
- Modify: `Sources/CallLane/Controller.swift` (full rewrite below)
- Modify: `Sources/CallLane/AudioSystem.swift` (protocol shrinks)
- Modify: `Tests/CallLaneTests/FakeAudioSystem.swift`
- Create: `Tests/CallLaneTests/FakeEngine.swift`
- Test: `Tests/CallLaneTests/ControllerTests.swift` (full rewrite below)

**Interfaces:**
- Consumes: `EngineControl` from Task 4; `deviceID(forUID:)`, `driverVersion()` from Task 3.
- Produces on `Controller`: `static let callsUID = "CallLane_UID"`, `static let tapUID = "CallLane_2_UID"`, `static let legacyUID = "dev.rav4nn.calllane.calls"`, `init(audio: AudioSystem, engine: EngineControl, defaults: UserDefaults = .standard, appVersion: String = ...)`, `var defaultOutputDevice: AudioDevice?`, `var driverStatus: String?`. Removed: `callsName`, `callsWraps`, `removeCallsDevice()`.
- Removed from `protocol AudioSystem`: `createAggregate`, `aggregateSubDeviceUID`, `setAggregateSubDevice`, `setName`. `destroyAggregate` stays (migration). `createAggregate` stays on `CoreAudioSystem` only, for the live test.
- Produces `FakeEngine` with `var running: (tap: AudioObjectID, destination: AudioObjectID)?`, `var starts: Int`, `var failStart: Bool`.

- [ ] **Step 1: Write FakeEngine**

`Tests/CallLaneTests/FakeEngine.swift`:

```swift
import CoreAudio
@testable import CallLane

final class FakeEngine: EngineControl {
    var running: (tap: AudioObjectID, destination: AudioObjectID)?
    var starts = 0
    var failStart = false

    func start(tap: AudioObjectID, destination: AudioObjectID) throws {
        if failStart { throw AudioError(what: "start engine", status: -1) }
        if let r = running, r.tap == tap, r.destination == destination { return }
        running = (tap, destination)
        starts += 1
    }

    func stop() { running = nil }
}
```

- [ ] **Step 2: Write the failing controller tests**

Replace the whole of `Tests/CallLaneTests/ControllerTests.swift` with:

```swift
import Testing
import Foundation
import CoreAudio
@testable import CallLane

@Suite struct ControllerTests {
    let fake = FakeAudioSystem()
    let engine = FakeEngine()
    let defaults: UserDefaults
    let speakers: AudioObjectID
    let airpods: AudioObjectID
    let mic: AudioObjectID
    let calls: AudioObjectID
    let tap: AudioObjectID

    init() {
        let suite = "dev.rav4nn.calllane.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        speakers = fake.addDevice("Speakers", uid: "spk")
        airpods = fake.addDevice("AirPods", uid: "ap:out")
        mic = fake.addDevice("Mac Mic", uid: "mic", input: true, output: false)
        calls = fake.addDevice("CallLane", uid: Controller.callsUID, transport: kAudioDeviceTransportTypeUSB)
        tap = fake.addDevice("CallLane Tap", uid: Controller.tapUID, input: true, output: false, transport: kAudioDeviceTransportTypeUSB)
        fake.defaultOut = airpods
        fake.defaultIn = mic
        fake.inputVolumes[mic] = 1.0
    }

    func makeController(appVersion: String = "0.2.0") -> Controller {
        let c = Controller(audio: fake, engine: engine, defaults: defaults, appVersion: appVersion)
        c.reconcile()
        return c
    }

    // MARK: pickers

    @Test func hidesOwnDevicesFromPickers() {
        let c = makeController()
        #expect(c.callsDevice?.id == calls)
        #expect(!c.outputs.contains { $0.id == calls })
        #expect(!c.inputs.contains { $0.id == tap })
        #expect(c.defaultOutputDevice?.id == airpods)
    }

    // MARK: CallLane must never be the system output

    @Test func callsAsDefaultOutputRevertsToPreviousOutput() {
        let c = makeController()
        fake.defaultOut = calls
        c.reconcile()
        #expect(fake.defaultOut == airpods)
        #expect(c.status.contains("call apps only"))
    }

    @Test func callsAsDefaultFallsBackToAnyRealOutputWhenPreviousIsGone() {
        let c = makeController()
        fake.remove(airpods)
        fake.defaultOut = calls
        c.reconcile()
        #expect(fake.defaultOut == speakers)
    }

    @Test func statusClearsWhenTheUserPicksAnotherOutput() {
        let c = makeController()
        fake.defaultOut = calls
        c.reconcile()
        #expect(!c.status.isEmpty)
        c.selectOutput(speakers)
        #expect(c.status.isEmpty)
    }

    // MARK: migration from the v0.1 aggregate

    @Test func migrationDestroysTheOldAggregate() {
        let old = fake.addDevice("CallLane", uid: Controller.legacyUID, transport: kAudioDeviceTransportTypeAggregate)
        let c = makeController()
        #expect(fake.list.first { $0.id == old } == nil)
        #expect(c.callsDevice?.id == calls)
    }

    @Test func migrationMovesTheOutputOffTheOldAggregateFirst() {
        let old = fake.addDevice("CallLane", uid: Controller.legacyUID, transport: kAudioDeviceTransportTypeAggregate)
        fake.defaultOut = old
        _ = makeController()
        #expect(fake.defaultOut == speakers || fake.defaultOut == airpods)
        #expect(fake.list.first { $0.id == old } == nil)
    }

    @Test func migrationIgnoresAForeignDeviceWithTheOldUID() {
        let usb = fake.addDevice("Odd", uid: Controller.legacyUID, transport: kAudioDeviceTransportTypeUSB)
        _ = makeController()
        #expect(fake.list.first { $0.id == usb } != nil, "only aggregates are destroyed")
    }

    // MARK: driver check

    @Test func driverPresentAndCurrentHasNoDriverStatus() {
        #expect(makeController().driverStatus == nil)
    }

    @Test func missingDriverSetsDriverStatus() {
        fake.remove(calls)
        fake.remove(tap)
        let c = makeController()
        #expect(c.driverStatus?.hasPrefix("Driver not installed.") == true)
        #expect(c.driverStatus?.contains("make install-driver") == true)
    }

    @Test func missingTapAloneCountsAsMissingDriver() {
        fake.remove(tap)
        #expect(makeController().driverStatus?.hasPrefix("Driver not installed.") == true)
    }

    @Test func olderDriverAsksForReinstall() {
        fake.installedDriverVersion = "0.1.0"
        let c = makeController(appVersion: "0.2.0")
        #expect(c.driverStatus == "Driver is v0.1.0, app is v0.2.0. Reinstall the cask.")
    }

    @Test func newerDriverIsFine() {
        fake.installedDriverVersion = "0.10.0"
        #expect(makeController(appVersion: "0.2.0").driverStatus == nil)
    }

    // MARK: engine lifecycle

    @Test func engineStartsOnInUseAndStopsOnIdle() {
        let c = makeController()
        #expect(engine.running == nil)
        fake.running.insert(calls)
        c.reconcile()
        #expect(c.callsInUse)
        #expect(engine.running?.tap == tap)
        #expect(engine.running?.destination == airpods)
        fake.running.remove(calls)
        c.reconcile()
        #expect(!c.callsInUse)
        #expect(engine.running == nil)
    }

    @Test func engineFollowsTheDefaultOutputWhileInUse() {
        let c = makeController()
        fake.running.insert(calls)
        c.reconcile()
        fake.defaultOut = speakers
        c.reconcile()
        #expect(engine.running?.destination == speakers)
        #expect(engine.starts == 2)
    }

    @Test func engineDoesNotStartWithoutATap() {
        fake.remove(tap)
        let c = makeController()
        fake.running.insert(calls)
        c.reconcile()
        #expect(engine.running == nil)
    }

    @Test func engineFailureIsVisibleAndClearsOnSuccess() {
        let c = makeController()
        engine.failStart = true
        fake.running.insert(calls)
        c.reconcile()
        #expect(c.status.contains("Could not start the audio engine"))
        engine.failStart = false
        c.reconcile()
        #expect(c.status.isEmpty)
        #expect(engine.running != nil)
    }

    // MARK: in-use listener

    @Test func callStartFlipsInUseWithoutPanelOpen() {
        let c = makeController()
        c.start()
        let fire = fake.handlers[calls]?[kAudioDevicePropertyDeviceIsRunningSomewhere]
        #expect(fire != nil, "running listener is registered on the CallLane device itself")
        #expect(!c.callsInUse)
        fake.running.insert(calls)
        fire?()
        #expect(c.callsInUse)
        #expect(engine.running != nil)
        fake.running.remove(calls)
        fire?()
        #expect(!c.callsInUse)
        #expect(engine.running == nil)
    }

    @Test func reloadedDriverGetsAFreshRunningListener() {
        let c = makeController()
        c.start()
        fake.remove(calls)                       // coreaudiod restarted: new object ids
        fake.remove(tap)
        let newCalls = fake.addDevice("CallLane", uid: Controller.callsUID, transport: kAudioDeviceTransportTypeUSB)
        fake.addDevice("CallLane Tap", uid: Controller.tapUID, input: true, output: false, transport: kAudioDeviceTransportTypeUSB)
        c.reconcile()
        #expect(newCalls != calls)
        #expect(fake.handlers[newCalls]?[kAudioDevicePropertyDeviceIsRunningSomewhere] != nil)
    }

    // MARK: input lock (unchanged behaviour)

    @Test func inputLockRevertsAndRestoresVolume() {
        let c = makeController()
        c.inputLocked = true
        let btMic = fake.addDevice("AirPods", uid: "ap:in", input: true, output: false)
        fake.defaultIn = btMic
        fake.inputVolumes[mic] = 0.3
        c.reconcile()
        #expect(fake.defaultIn == mic)
        #expect(fake.inputVolumes[mic] == 1.0)
    }

    @Test func inputLockIgnoresAbsentDevice() {
        let c = makeController()
        c.inputLocked = true
        let usb = fake.addDevice("USB", uid: "usb", input: true, output: false)
        fake.remove(mic)
        fake.defaultIn = usb
        c.reconcile()
        #expect(fake.defaultIn == usb)
    }

    @Test func inputLockFailureIsVisible() {
        let c = makeController()
        c.inputLocked = true
        let btMic = fake.addDevice("AirPods", uid: "ap:in", input: true, output: false)
        fake.defaultIn = btMic
        fake.failSetDefaultInput = true
        c.reconcile()
        #expect(fake.defaultIn == btMic)
        #expect(c.status.contains("Could not lock input"))
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd /Users/rav4nn/work/projects/calllane && make test 2>&1 | grep -E "error:" | head -5`
Expected: `extra argument 'engine' in call` and `has no member 'legacyUID'`.

- [ ] **Step 4: Shrink the AudioSystem protocol and the fake**

In `Sources/CallLane/AudioSystem.swift`, delete these four lines from `protocol AudioSystem`:

```swift
    func createAggregate(name: String, uid: String, subDeviceUID: String) throws -> AudioObjectID
    func aggregateSubDeviceUID(_ id: AudioObjectID) -> String?
    func setAggregateSubDevice(_ id: AudioObjectID, uid: String) throws
    func setName(_ id: AudioObjectID, _ name: String) throws
```

Keep `func destroyAggregate(_ id: AudioObjectID) throws` in the protocol. In `CoreAudioSystem`, delete the bodies of `aggregateSubDeviceUID`, `setAggregateSubDevice`, and `setName`. Keep `createAggregate` and put this comment above it:

```swift
    /// Not part of `AudioSystem` any more: the app stopped creating aggregates in v0.2.
    /// The live test still creates one to exercise `deviceID(forUID:)` and `destroyAggregate`.
```

In `Tests/CallLaneTests/FakeAudioSystem.swift`, delete the `aggregates` property and the functions `createAggregate`, `aggregateSubDeviceUID`, `setAggregateSubDevice`, `setName`. Replace `destroyAggregate` with:

```swift
    func destroyAggregate(_ id: AudioObjectID) throws { remove(id) }
```

- [ ] **Step 5: Rewrite Controller.swift**

Replace the whole file with:

```swift
import CoreAudio
import Foundation
import Observation

@Observable
final class Controller {
    /// The driver's output device, the one call apps pick.
    static let callsUID = "CallLane_UID"
    /// Its hidden input twin, the one the engine reads.
    static let tapUID = "CallLane_2_UID"
    /// The v0.1 aggregate device. Destroyed on sight.
    static let legacyUID = "dev.rav4nn.calllane.calls"
    private static let ownUIDs: Set<String> = [callsUID, tapUID, legacyUID]

    private let audio: AudioSystem
    private let engine: EngineControl
    private let defaults: UserDefaults
    private let appVersion: String
    private var tokens: [ListenerToken] = []
    private var runningToken: ListenerToken?
    private var runningWatched: AudioObjectID?
    private var pending: DispatchWorkItem?
    /// The last real output the user had; where the system output goes back to when CallLane
    /// must not stay the system output.
    private var lastRealOutput: AudioObjectID?
    private var tapID: AudioObjectID?
    private var driverVersion: String?

    private(set) var devices: [AudioDevice] = []
    private(set) var defaultOutputID: AudioObjectID?
    private(set) var defaultInputID: AudioObjectID?
    private(set) var outputVolume: Float?
    private(set) var callsInUse = false
    private(set) var status = ""

    init(audio: AudioSystem, engine: EngineControl, defaults: UserDefaults = .standard,
         appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0") {
        self.audio = audio
        self.engine = engine
        self.defaults = defaults
        self.appVersion = appVersion
    }

    // MARK: derived

    var outputs: [AudioDevice] { devices.filter { $0.hasOutput && !Self.ownUIDs.contains($0.uid) } }
    var inputs: [AudioDevice] { devices.filter { $0.hasInput && !Self.ownUIDs.contains($0.uid) } }
    var callsDevice: AudioDevice? { devices.first { $0.uid == Self.callsUID } }
    var defaultOutputDevice: AudioDevice? { devices.first { $0.id == defaultOutputID } }

    /// Non-nil when the driver is absent or older than the app. The panel shows it in place of
    /// the CallLane status row.
    var driverStatus: String? {
        if callsDevice == nil || tapID == nil {
            return "Driver not installed. Run `make install-driver` or reinstall the cask."
        }
        if let v = driverVersion, v.compare(appVersion, options: .numeric) == .orderedAscending {
            return "Driver is v\(v), app is v\(appVersion). Reinstall the cask."
        }
        return nil
    }

    var inputLocked: Bool {
        get { defaults.string(forKey: "lockedInputUID") != nil }
        set {
            if newValue, let id = audio.defaultInput(), let dev = devices.first(where: { $0.id == id }) {
                defaults.set(dev.uid, forKey: "lockedInputUID")
                defaults.set(audio.volume(id, scope: .input) ?? 1, forKey: "lockedInputVolume")
            } else {
                defaults.removeObject(forKey: "lockedInputUID")
            }
            reconcile()
        }
    }

    // MARK: lifecycle

    func start() {
        reconcile()
        for sel in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice] {
            if let t = audio.listen(AudioObjectID(kAudioObjectSystemObject), sel, { [weak self] in self?.scheduleReconcile() }) {
                tokens.append(t)
            }
        }
    }

    // Bluetooth connects fire a burst of events; run once after the burst.
    private func scheduleReconcile() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.reconcile() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    // MARK: rules — idempotent, safe to call at any time

    func reconcile() {
        refresh()
        trackRealOutput()
        migrateLegacy()
        keepCallsOffSystemOutput()
        reconcileInputLock()
        refresh()
        outputVolume = defaultOutputID.flatMap { audio.volume($0, scope: .output) }
        callsInUse = callsDevice.map { audio.isRunningSomewhere($0.id) } ?? false
        reconcileEngine()
        watchRunning()
    }

    /// A call app opening CallLane fires no system-level event, so watch the device itself.
    /// The device gets a new id whenever coreaudiod restarts; re-register when that happens.
    private func watchRunning() {
        guard callsDevice?.id != runningWatched else { return }
        runningToken = nil
        runningWatched = nil
        guard let calls = callsDevice else { return }
        runningToken = audio.listen(calls.id, kAudioDevicePropertyDeviceIsRunningSomewhere) { [weak self] in self?.reconcile() }
        if runningToken != nil { runningWatched = calls.id }   // a failed registration retries next reconcile
    }

    private func refresh() {
        devices = audio.devices()
        defaultOutputID = audio.defaultOutput()
        defaultInputID = audio.defaultInput()
        tapID = audio.deviceID(forUID: Self.tapUID)   // hidden: never trust the device list for it
        driverVersion = audio.driverVersion()
    }

    /// Remembers the user's real output. A change of real output also clears any old message:
    /// that is when the user has acted on it.
    private func trackRealOutput() {
        guard let id = defaultOutputID, outputs.contains(where: { $0.id == id }), id != lastRealOutput else { return }
        lastRealOutput = id
        status = ""
    }

    /// Runs one CoreAudio write that enforces an app invariant. A failure is never silent:
    /// it lands in `status` for the menu and in the log.
    @discardableResult
    private func attempt(_ what: String, _ op: () throws -> Void) -> Bool {
        do { try op(); return true } catch {
            status = "\(what): \(error)"
            log.error("\(what): \(String(describing: error))")
            return false
        }
    }

    private var fallbackOutput: AudioDevice? {
        outputs.first { $0.id == lastRealOutput } ?? outputs.first
    }

    /// v0.1 created an aggregate device with this UID. Next to the driver's device it would
    /// only confuse the pickers, so destroy it. Move the system output off it first.
    private func migrateLegacy() {
        guard let old = devices.first(where: { $0.uid == Self.legacyUID && $0.isAggregate }) else { return }
        if defaultOutputID == old.id {
            guard let real = fallbackOutput,
                  attempt("Could not leave the old CallLane device", { try audio.setDefaultOutput(real.id) }) else { return }
        }
        attempt("Could not remove the old CallLane device", { try audio.destroyAggregate(old.id) })
    }

    /// CallLane must never be the system output: the engine would copy the device into itself.
    private func keepCallsOffSystemOutput() {
        guard let calls = callsDevice, defaultOutputID == calls.id else { return }
        guard let real = fallbackOutput else {
            status = "CallLane is the system output and no other output exists."
            return
        }
        if attempt("Could not leave CallLane", { try audio.setDefaultOutput(real.id) }) {
            status = "CallLane is for call apps only. Output set back to \(real.name)."
        }
    }

    /// Copies the tap onto the real output while a call app uses CallLane; stops when idle.
    /// The engine restarts on its own when the destination changes.
    private func reconcileEngine() {
        guard callsInUse, let tap = tapID, let out = defaultOutputID, out != callsDevice?.id else {
            engine.stop()
            return
        }
        let what = "Could not start the audio engine"
        if attempt(what, { try engine.start(tap: tap, destination: out) }), status.hasPrefix(what) {
            status = ""
        }
    }

    private func reconcileInputLock() {
        guard let uid = defaults.string(forKey: "lockedInputUID"),
              let locked = devices.first(where: { $0.uid == uid && $0.hasInput }) else { return }
        if defaultInputID != locked.id {
            attempt("Could not lock input to \(locked.name)", { try audio.setDefaultInput(locked.id) })
        }
        let level = defaults.object(forKey: "lockedInputVolume") as? Float ?? 1
        if let current = audio.volume(locked.id, scope: .input), abs(current - level) > 0.01 {
            attempt("Could not restore input volume", { try audio.setVolume(locked.id, scope: .input, level) })
        }
    }

    // MARK: user actions

    func selectOutput(_ id: AudioObjectID) {
        try? audio.setDefaultOutput(id)
        reconcile()
    }

    func selectInput(_ id: AudioObjectID) {
        try? audio.setDefaultInput(id)
        if inputLocked, let dev = devices.first(where: { $0.id == id }) {
            defaults.set(dev.uid, forKey: "lockedInputUID")
            defaults.set(audio.volume(id, scope: .input) ?? 1, forKey: "lockedInputVolume")
        }
        reconcile()
    }

    func setOutputVolume(_ value: Float) {
        guard let id = defaultOutputID else { return }
        try? audio.setVolume(id, scope: .output, value)
        outputVolume = audio.volume(id, scope: .output)
    }
}
```

- [ ] **Step 6: Run the tests**

Run: `cd /Users/rav4nn/work/projects/calllane && make test 2>&1 | tail -20`
Expected: `MenuView.swift` and `App.swift` fail to compile (`callsWraps`, `removeCallsDevice`, missing `engine:` argument). That is Task 6's job. To see the controller tests pass now, apply Task 6 Step 1 and Step 2 first, then re-run. All `ControllerTests`, `RingTests`, `AudioSystemTests`, and `EngineTests` must pass before the commit below.

- [ ] **Step 7: Review and commit (together with Task 6 Steps 1 and 2 if they were needed to compile)**

Run the Codex review per the `codex-review-protocol` skill, apply the good fixes, re-run `make test`, run `codex-receipt`, then:

```bash
cd /Users/rav4nn/work/projects/calllane
git add Sources Tests
git commit -m "controller: driver-backed CallLane; migrate the aggregate away, run the engine while in use"
```

---

### Task 6: App wiring, panel, setup guide, screenshots

**Files:**
- Modify: `Sources/CallLane/App.swift:14`
- Modify: `Sources/CallLane/MenuView.swift:66-73` (footer) and `:175-195` (calls section)
- Modify: `Sources/CallLane/SetupView.swift:4-11` (apps) and `:38` (footnote)
- Modify: `docs/panel-light.png`, `docs/panel-dark.png`

**Interfaces:**
- Consumes: `Controller.init(audio:engine:)`, `controller.driverStatus`, `controller.defaultOutputDevice`, `Engine()` from Tasks 4 and 5.

- [ ] **Step 1: Wire the engine into the app**

In `Sources/CallLane/App.swift`, replace line 14:

```swift
        controller = Controller(audio: CoreAudioSystem(), engine: Engine())
```

- [ ] **Step 2: Update the panel**

In `Sources/CallLane/MenuView.swift`, replace the footer block (the `Divider()` plus the `VStack` that holds the two `footerButton` calls, lines 66-73) with:

```swift
            Divider()
            footerButton("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
```

Replace `private var calls: some View { ... }` (lines 175-195) with:

```swift
    private var calls: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let problem = controller.driverStatus {
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                        .padding(.top, 6)
                    Text(problem)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 8) {
                    Circle()
                        .fill(controller.callsInUse ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 7, height: 7)
                    Text("CallLane → \(controller.defaultOutputDevice?.name ?? "no output")")
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(controller.callsInUse ? "in use" : "idle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !controller.status.isEmpty {
                note(controller.status, color: .orange)
            }
            note("Pick “CallLane” as the speaker in each call app.")
        }
    }
```

- [ ] **Step 3: Update the setup guide**

In `Sources/CallLane/SetupView.swift`, replace the `apps` array with:

```swift
    private let apps: [(String, String)] = [
        ("WhatsApp", "Settings → Calls → Speaker → CallLane"),
        ("FaceTime", "Menu bar → Video → Output → CallLane"),
        ("Zoom", "Settings → Audio → Speaker → CallLane"),
        ("Google Meet (Chrome)", "In a call: speaker menu in the bottom bar → CallLane. Or ⋮ → Settings → Audio → Speakers"),
        ("Slack", "Preferences → Audio & video → Speaker → CallLane"),
        ("Microsoft Teams", "Settings → Devices → Speaker → CallLane"),
        ("Discord", "User Settings → Voice & Video → Output Device → CallLane"),
    ]
```

Replace the footnote string on line 38 with:

```swift
            Text("Safari has no per-site speaker picker, so calls in Safari cannot use CallLane.")
```

- [ ] **Step 4: Build, test, and run the dev build**

```bash
cd /Users/rav4nn/work/projects/calllane
make test 2>&1 | tail -5
pkill -x CallLane; make run
```

Expected: all suites pass. The menu bar phone icon appears. The panel shows `CallLane → <your output>` and `idle`, no driver message, and a single `Quit` in the footer. Ask the user to place a WhatsApp call with speaker `CallLane`: the icon fills, the row reads `in use`, and the call plays through the AirPods.

- [ ] **Step 5: Refresh the screenshots**

```bash
cd /Users/rav4nn/work/projects/calllane
make snap && cp build/panel-light.png build/panel-dark.png docs/
```

Expected: `wrote build/panel-light.png` and `wrote build/panel-dark.png`. If the script reports no preview window, the terminal lacks Screen Recording; tell the user and continue. The screenshots then go into a later commit.

- [ ] **Step 6: Review and commit**

Run the Codex review per the `codex-review-protocol` skill, apply the good fixes, re-run `make test`, run `codex-receipt`, then:

```bash
cd /Users/rav4nn/work/projects/calllane
git add Sources docs/panel-light.png docs/panel-dark.png
git commit -m "panel: driver status row, WhatsApp back in the setup guide, Quit only"
```

---

### Task 7: Version 0.2.0, release bundle, workflow, cask, README, licence text

**Files:**
- Modify: `Sources/CallLane/Info.plist:10-11`
- Modify: `Makefile` (`release` target, `.PHONY`)
- Modify: `.github/workflows/release.yml`
- Modify: `Casks/calllane.rb`
- Modify: `README.md` (full rewrite below)

**Interfaces:**
- Produces: `build/CallLane.zip` with `CallLane.app` and `CallLaneDriver.pkg` at its root. Cask template for the tap.

- [ ] **Step 1: Bump the version**

In `Sources/CallLane/Info.plist`, set:

```xml
    <key>CFBundleShortVersionString</key><string>0.2.0</string>
    <key>CFBundleVersion</key><string>2</string>
```

- [ ] **Step 2: Make `release` ship the package too**

Replace the `release` target in `Makefile` with:

```make
release: build pkg
	rm -rf $(BUILD)/dist && mkdir -p $(BUILD)/dist
	cp -R $(BUNDLE) $(BUILD)/dist/
	cp $(PKG) $(BUILD)/dist/
	cd $(BUILD)/dist && ditto -c -k . ../$(APP).zip
	shasum -a 256 $(BUILD)/$(APP).zip
```

Check:

```bash
cd /Users/rav4nn/work/projects/calllane
make release 2>&1 | tail -2
unzip -l build/CallLane.zip | grep -E "CallLane.app/$|CallLaneDriver.pkg"
/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' build/CallLane.driver/Contents/Info.plist
```

Expected: the zip lists `CallLane.app/` and `CallLaneDriver.pkg` at the root, and the driver plist reads `0.2.0`.

- [ ] **Step 3: Update the workflow**

Replace `.github/workflows/release.yml` with:

```yaml
name: release
on:
  push:
    tags: ["v*"]
jobs:
  build:
    runs-on: macos-15
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      # Live CoreAudio suites need a real output device; EngineTests skips itself without the driver.
      - run: swift test --skip AudioSystemTests
      - run: make release   # builds the app, the driver, and the package
      - name: Note the cask sha
        run: shasum -a 256 build/CallLane.zip > build/sha256.txt
      - uses: softprops/action-gh-release@v2
        with:
          files: |
            build/CallLane.zip
            build/sha256.txt
          body_path: build/sha256.txt
```

- [ ] **Step 4: Update the cask template**

Replace `Casks/calllane.rb` with:

```ruby
# Copy into rav4nn/homebrew-tap/Casks/ after each release and fill in sha256 from the release notes.
cask "calllane" do
  version "0.2.0"
  sha256 "FILL_IN_FROM_RELEASE_NOTES"

  url "https://github.com/rav4nn/calllane/releases/download/v#{version}/CallLane.zip"
  name "CallLane"
  desc "Menu bar app that stops call audio ducking with a CallLane output device"
  homepage "https://github.com/rav4nn/calllane"

  depends_on macos: :sonoma

  app "CallLane.app"
  pkg "CallLaneDriver.pkg"

  # Homebrew runs `script` before `pkgutil`, so the script removes the bundle and restarts
  # the audio daemon itself; pkgutil then forgets the receipt.
  uninstall quit:    "dev.rav4nn.calllane",
            script:  {
              executable: "/bin/sh",
              args:       ["-c", "rm -rf /Library/Audio/Plug-Ins/HAL/CallLane.driver; killall coreaudiod"],
              sudo:       true,
            },
            pkgutil: "dev.rav4nn.calllane.driver"

  zap trash: "~/Library/Preferences/dev.rav4nn.calllane.plist"

  caveats <<~EOS
    The CallLane driver package asks for your admin password once.

    CallLane is signed ad-hoc. Clear the quarantine flag before the first launch:
      xattr -dr com.apple.quarantine /Applications/CallLane.app
    or allow the app under System Settings → Privacy & Security after it is blocked.
  EOS
end
```

This differs from the spec's stanza on purpose: the spec listed `pkgutil` first and `script` last, but Homebrew applies uninstall directives in a fixed order with `script` before `pkgutil`, so a bare `killall` would restart the daemon while the driver files are still in place.

Lint:

```bash
brew style /Users/rav4nn/work/projects/calllane/Casks/calllane.rb
```

Expected: no offenses. If `brew style` reorders keys, accept its `--fix` output.

- [ ] **Step 5: Rewrite the README**

Replace `README.md` with:

````markdown
# CallLane

Two things go wrong every time you join a call on a Mac with Bluetooth headphones.

1. **Your media gets quiet.** macOS lowers every other sound by about 20 dB the moment
   a call app starts, and there is no setting to stop it. Music, video, and games stay
   quiet until the call ends.
2. **Your headphones drop to headset quality.** The call app switches to the headphones'
   microphone. Bluetooth cannot stream high-quality audio and carry a mic at the same
   time, so the headphones fall back to the low-quality headset profile. The MacBook's
   built-in mic sounds better anyway.

CallLane fixes both from the menu bar.

- It gives call apps their own output device, `CallLane`. The app copies whatever plays
  on it onto your real headphones. macOS ducks only the audio on the call app's device,
  so everything else stays at full volume.
- It locks the input to the mic you choose, so your headphones stay in the
  high-quality listening profile.

A small user-space audio driver, no kernel extension, one admin password at install.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/panel-dark.png">
  <img src="docs/panel-light.png" alt="CallLane panel: output and input pickers, volume slider, CallLane status row" width="340">
</picture>

## Install

```sh
brew trust --tap rav4nn/tap
brew install --cask rav4nn/tap/calllane
xattr -dr com.apple.quarantine /Applications/CallLane.app
```

The cask installs the app and the `CallLane` driver package. The package asks for your
admin password once and restarts the audio daemon; no reboot.

`brew trust` is needed on Homebrew 6, which loads third-party casks only from
taps you trust. The `xattr` line is needed because CallLane is signed ad-hoc, not
with an Apple Developer ID, and Homebrew 6 always quarantines downloads. Without
it, macOS shows "cannot verify" and you must allow the app under
System Settings → Privacy & Security.

Or build from source with the Xcode Command Line Tools: `git clone`, then
`make install-driver` (asks for sudo) and `make run`.

## Use

1. Launch CallLane. A phone icon appears in the menu bar.
2. In each call app, pick `CallLane` as the speaker. Once per app. The setup guide in the
   menu lists the exact path for WhatsApp, FaceTime, Zoom, Meet, Slack, Teams, Discord.
3. Keep your headphones as the system output. Keep the microphone on your Mac's
   built-in mic or a USB mic, and turn on Lock input.

The phone icon fills while a call app uses `CallLane`.

## How it works

`CallLane` is a CoreAudio server plugin derived from BlackHole. It exposes an output
device that reports a USB transport, which is what makes it show up in pickers that list
only physical devices, such as WhatsApp for Mac. Audio written to it lands in a ring
inside the audio daemon. A hidden twin device reads that ring. While a call app uses
`CallLane`, the app copies the twin onto your current default output, 128 frames at a
time. The copy adds about 10 to 15 ms.

The volume keys still work during a call. They change the volume of your headphones,
and the call plays through those headphones, so the call follows.

## Limits

- Apple does not document that ducking stops at the device boundary. A macOS update
  could change this.
- Volume keys do nothing while `CallLane` is the system output. CallLane reverts that
  selection and tells you.
- Safari has no per-site speaker picker, so calls in Safari cannot use `CallLane`.
- `CallLane` runs at 48 kHz. Every call app handles that.
- Spatial Audio and head tracking may not apply to the call on `CallLane`.
- Tested on macOS 26 with AirPods Pro 3. Runs on macOS 14 and later.

## Uninstall

`brew uninstall --cask calllane` removes the app and the driver and restarts the audio
daemon. From a source build: `sudo rm -rf /Library/Audio/Plug-Ins/HAL/CallLane.driver`
then `sudo killall coreaudiod`.

## Licence

The app is MIT (see `LICENSE`). The driver in `Driver/` is a derivative of
[BlackHole](https://github.com/ExistentialAudio/BlackHole) by Existential Audio Inc.
and is GPL-3 (see `Driver/LICENSE` and `Driver/NOTICE`).
````

- [ ] **Step 6: Review and commit**

Run the Codex review per the `codex-review-protocol` skill, apply the good fixes, run `make test`, run `codex-receipt`, then:

```bash
cd /Users/rav4nn/work/projects/calllane
git add Sources/CallLane/Info.plist Makefile .github/workflows/release.yml Casks/calllane.rb README.md
git commit -m "release: v0.2.0 ships the driver package in the zip and the cask"
```

---

### Task 8: Manual acceptance, review card, release

**Files:**
- Modify (tap repo, after the GitHub release exists): `/Users/rav4nn/work/projects/homebrew-tap/Casks/calllane.rb`

- [ ] **Step 1: Reinstall the 0.2.0 driver and run the dev build**

The installed driver still reports 0.1.0 from Task 2. Ask the user to run:

```bash
cd /Users/rav4nn/work/projects/calllane && make install-driver
```

Then:

```bash
cd /Users/rav4nn/work/projects/calllane && pkill -x CallLane; make run
```

Expected: no driver message in the panel. Note: `/Applications/CallLane.app` is still v0.1.0 from brew; it must not run at the same time (`pkill -x CallLane` covers both).

- [ ] **Step 2: Acceptance checklist with the user**

Ask the user to check each item and report:

1. WhatsApp: Settings → Calls → Speaker lists `CallLane`. A call plays through the AirPods, media stays loud, delay not noticeable, volume keys work.
2. Google Meet in Chrome with speaker `CallLane`: same.
3. FaceTime with output `CallLane`: same.
4. During a call, switch the system output to the MacBook speakers: the call follows within a second.
5. Pick `CallLane` as the system output: it reverts and the panel says so.
6. AirPods stay at 48 kHz during the call (Audio MIDI Setup).
7. After the call ends the panel reads `idle` and the phone icon empties.

- [ ] **Step 3: Print the review card and idle**

Every push waits for the user. Card contents: what changed (driver, engine, controller, panel, release), what to poke (the acceptance list above), the line `cd /Users/rav4nn/work/projects/calllane && lgtm`, and the note that the two docs commits from 2026-09-11 (5dc0f65, 6a94742) go out with this push.

- [ ] **Step 4: After the user's `lgtm` and push: tag**

Only after the user says the push is done:

```bash
cd /Users/rav4nn/work/projects/calllane
git tag v0.2.0
```

The tag push needs its own approval at the same sha; `git push origin main v0.2.0` passes the gate once main is approved (the gate reads the first refspec). Ask the user to run the push.

- [ ] **Step 5: Update the tap after the workflow finishes**

```bash
gh run list --repo rav4nn/calllane --limit 1
gh release view v0.2.0 --repo rav4nn/calllane --json body -q .body
```

Copy the sha into `Casks/calllane.rb`, copy the file into `/Users/rav4nn/work/projects/homebrew-tap/Casks/calllane.rb`, then in the tap repo:

```bash
cd /Users/rav4nn/work/projects/homebrew-tap
brew style Casks/calllane.rb
brew fetch --cask ./Casks/calllane.rb
```

Expected: no offenses, and the fetch's sha matches. Commit the tap change (`CODEX_SKIP_REVIEW=1` is fine: one sha and one version line) and print a second review card with `cd /Users/rav4nn/work/projects/homebrew-tap && lgtm`.

- [ ] **Step 6: Upgrade the brew install on this Mac and update memory**

After the tap push, ask the user to run `brew upgrade --cask calllane`, then quit the dev build and launch `/Applications/CallLane.app`. Then update the auto-memory note `airpods-call-audio.md`: the device is now a BlackHole-derived HAL plugin with transport USB, not an aggregate, and WhatsApp lists only physical transport types.

---

## Self-review

- **Spec coverage.** Driver source, defines, UIDs, bundle and version: Task 1. Package, postinstall, install target: Task 2. Engine with two HAL units, format, buffer sizes, ring and drift control, start/stop semantics: Task 4. Controller rules 1-5, `EngineControl` protocol, driver check and version compare: Task 5. Panel status row, driver row, Quit-only footer, setup guide with WhatsApp: Task 6. `make release`, workflow, cask, README install note and licence paragraph, licence files: Tasks 1 and 7. Testing section: Ring and Controller unit tests (Tasks 4, 5), Engine live test with trait skip (Task 4), driver compile in CI (Task 7), manual checks (Tasks 2, 8).
- **Deliberate deviations from the spec, each stated where it happens.** The ring uses `NSLock`, not a lock-free structure (Task 4, `ponytail:` comment). The driver status lives in `driverStatus`, not in `status`, so a driver problem never fights with the rule messages (Task 5). The live engine test does not change the system output; it points the tone at `CallLane` directly (Task 4). The cask `uninstall` stanza removes the bundle inside `script` because of Homebrew's fixed directive order (Task 7). `kSampleRates` is pinned to 48000 (Global Constraints).
- **Type consistency.** `EngineControl.start(tap:destination:)` and `stop()` are used with those labels in `Engine`, `FakeEngine`, and `Controller`. `deviceID(forUID:)` and `driverVersion()` are spelled the same in the protocol, `CoreAudioSystem`, and `FakeAudioSystem`. `Engine.format`, `Engine.current`, and `Engine.ring` are used by `EngineTests` as declared. `Controller.driverStatus`, `defaultOutputDevice`, `callsUID`, `tapUID`, `legacyUID` are used by `MenuView` and `ControllerTests` as declared.
