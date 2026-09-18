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

A small user-space audio driver, no kernel extension. Two prompts, once each: the admin
password when the driver installs, and microphone access at first launch. The app reads
its own hidden tap device like a microphone; it never touches your real mic.

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

1. Launch CallLane. A phone icon appears in the menu bar. Allow microphone access when
   asked: without it macOS hands the app silence and calls on `CallLane` stay mute.
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
- Google Meet in Chrome does not duck other audio by itself (Chrome runs its own echo
  cancelling). For Meet, CallLane only stops the headset-quality drop.
- `CallLane` runs at 48 kHz. Every call app handles that.
- Spatial Audio and head tracking may not apply to the call on `CallLane`.
- Tested on macOS 26 with AirPods Pro 3. Runs on macOS 14 and later.

## Uninstall

`brew uninstall --cask calllane` removes the app and the driver and restarts the audio
daemon. From a source build: `make uninstall-driver`.

## Licence

The app is MIT (see `LICENSE`). The driver in `Driver/` is a derivative of
[BlackHole](https://github.com/ExistentialAudio/BlackHole) by Existential Audio Inc.
and is GPL-3 (see `Driver/LICENSE` and `Driver/NOTICE`).
