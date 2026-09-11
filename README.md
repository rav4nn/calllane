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

- It gives call apps their own output device, `CallLane`, that wraps your real
  headphones. macOS ducks only the audio on the call app's device, so everything else
  stays at full volume.
- It locks the input to the mic you choose, so your headphones stay in the
  high-quality listening profile.

No drivers. No kernel extensions. No permission prompts.

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

`brew trust` is needed on Homebrew 6, which loads third-party casks only from
taps you trust. The `xattr` line is needed because CallLane is signed ad-hoc, not
with an Apple Developer ID, and Homebrew 6 always quarantines downloads. Without
it, macOS shows "cannot verify" and you must allow the app under
System Settings → Privacy & Security.

Or build from source with the Xcode Command Line Tools: `git clone`, then `make run`.

## Use

1. Launch CallLane. A phone icon appears in the menu bar. It creates the `CallLane` device.
2. In each call app, pick `CallLane` as the speaker. Once per app. The setup guide in the
   menu lists the exact path for FaceTime, Zoom, Meet, Slack, Teams, Discord.
3. Keep your headphones as the system output. Keep the microphone on your Mac's
   built-in mic or a USB mic, and turn on Lock input.

The phone icon fills while a call app uses `CallLane`.

## How it works

`CallLane` is a public CoreAudio aggregate device with one sub-device: your current
default output. CallLane rewrites the sub-device whenever your output changes, so
`CallLane` always plays through the headphones you are on. Call apps remember `CallLane` by
its fixed UID across those changes.

The volume keys still work during a call. They change the volume of your headphones,
and the call plays through those headphones, so the call follows.

## Limits

- Apple does not document that ducking stops at the aggregate boundary. A macOS update
  could change this.
- Volume keys do nothing while `CallLane` is the system output. CallLane reverts that
  selection and tells you.
- Safari has no per-site speaker picker, so calls in Safari cannot use `CallLane`.
- WhatsApp is a Mac Catalyst app. Its speaker picker uses the iOS audio route API, which
  lists only physical devices, so `CallLane` never appears there.
- Spatial Audio and head tracking may not apply to the call on `CallLane`.
- Tested on macOS 26 with AirPods Pro 3. Runs on macOS 14 and later.

## Uninstall

Menu → "Remove CallLane device and quit", then `brew uninstall --cask calllane`.
If you skip the first step, remove the `CallLane` device in Audio MIDI Setup.

## License

MIT.
