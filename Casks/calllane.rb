# Template. `make release` renders build/calllane.rb with the version and sha filled in;
# the workflow uploads that file. Copy it into rav4nn/homebrew-tap/Casks/.
cask "calllane" do
  version "@VERSION@"
  sha256 "@SHA256@"

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
              args:       ["-c", "rm -rf /Library/Audio/Plug-Ins/HAL/CallLane.driver; killall coreaudiod || true"],
              sudo:       true,
            },
            pkgutil: "dev.rav4nn.calllane.driver"

  zap trash: "~/Library/Preferences/dev.rav4nn.calllane.plist"

  caveats <<~EOS
    The CallLane driver package asks for your admin password once. On first launch
    CallLane asks for microphone access: it reads its own hidden tap device, not your mic.

    CallLane is signed ad-hoc. Clear the quarantine flag before the first launch:
      xattr -dr com.apple.quarantine /Applications/CallLane.app
    or allow the app under System Settings → Privacy & Security after it is blocked.
  EOS
end
