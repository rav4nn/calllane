# CallLane: stop macOS audio ducking during calls and keep AirPods in high quality

**CallLane is a macOS menu-bar app that stops your Mac from lowering music and video during FaceTime, WhatsApp, Zoom, Microsoft Teams, Google Meet, Slack and Discord calls. It also keeps AirPods in high-quality sound when an app uses the mic.** Download it at **[calllane.app](https://calllane.app)**.

> This repository holds the documentation, release notes and the issue tracker for CallLane. The app is a paid, closed-source product. The audio driver it uses is open source at [rav4nn/calllane-driver](https://github.com/rav4nn/calllane-driver) (GPL-3.0).

## The two problems it fixes

### 1. Music and video go quiet when a call starts (audio ducking)

When a call app starts voice processing (echo cancellation for your mic), macOS lowers every other sound on the same output by about 20 dB until the call ends. Spotify, YouTube, a film or a game drops to about a tenth of its loudness. macOS has **no setting** to turn this off. The "Audio ducking" checkbox in VoiceOver Utility affects only VoiceOver speech, not calls.

**How CallLane fixes it:** call apps play into their own audio device, `CallLane`, which forwards the call to your real headphones or speakers. macOS ducks only that device, so music and video keep their full volume. The call adds about 10 to 15 ms of latency.

### 2. AirPods sound bad when an app uses the mic (headset mode)

When any app opens the AirPods microphone, Bluetooth switches from the high-quality listening profile (AAC, stereo) to the two-way headset profile (16 kHz mono). Music and the other person's voice start to sound like an old phone line. This happens with calls and with dictation apps such as **Wispr Flow, Superwhisper and MacWhisper**.

**How CallLane fixes it:** it locks the input to the mic you pick, for example the MacBook's built-in mic. If another app or macOS moves the input back to the AirPods, CallLane puts your mic back. The AirPods never leave high-quality mode.

## Works with

- Call apps: FaceTime, WhatsApp, Zoom, Microsoft Teams, Google Meet, Slack, Discord
- Dictation apps: Wispr Flow, Superwhisper, MacWhisper
- Headphones: AirPods and any Bluetooth headphones that drop to headset quality when their mic turns on. With wired headphones and speakers, CallLane still keeps media loud during calls.
- Mics: the Mac's built-in mic and USB mics

## Requirements

- macOS 14 Sonoma or later (tested on macOS 26 with AirPods Pro 3)
- Apple silicon or Intel
- No account, no kernel extension. Signed and notarized installer.

## Price

One-time purchase, no subscription. One license key works on up to 3 Macs. Free updates for version 1. 14-day refund, no questions asked. Current price: [calllane.app](https://calllane.app).

## Guides

- [How to turn off audio ducking on a Mac during calls](https://calllane.app/disable-audio-ducking-mac)
- [Why FaceTime turns your music down on a Mac](https://calllane.app/facetime-lowers-volume-mac)
- [WhatsApp calls make everything else quiet on a Mac](https://calllane.app/whatsapp-call-lowers-volume-mac)
- [Why AirPods sound bad during calls on a Mac](https://calllane.app/airpods-sound-bad-during-calls-mac)
- [VoiceOver audio ducking doesn't stop call ducking](https://calllane.app/voiceover-audio-ducking-not-working)

## FAQ

**Is there a macOS setting to stop audio ducking during calls?**
No. macOS has no setting for call ducking. The fix is to send the call to a separate output device, which CallLane does for you.

**Why do my AirPods sound like a phone call on my Mac?**
An app opened the AirPods mic, so Bluetooth switched to headset mode. Use another mic (for example the built-in mic) for input. CallLane keeps that choice locked.

**Why do AirPods sound bad with Wispr Flow or Superwhisper?**
The dictation app opens the AirPods mic each time you dictate. Lock the input to the Mac's mic with CallLane and the AirPods stay in high quality.

**Does CallLane record or send my audio anywhere?**
No. Audio stays on your Mac. CallLane has no account and no analytics.

**Does it replace SoundSource or Audio Hijack?**
No. Those are general audio tools. CallLane does one job: calls without ducking and without headset mode.

## Report a bug

[Open an issue](../../issues/new). Include your macOS version, your headphones and the call or dictation app. You can also use the Feedback row in CallLane's Settings, or email support@hardeep.cv.

## Releases

See [Releases](../../releases) for release notes. Download the latest version at [calllane.app](https://calllane.app).

---

Made by Hardeep Singh ([@rav4nn on X](https://x.com/rav4nn)). Not affiliated with Apple Inc. Copyright © 2026. All rights reserved.
