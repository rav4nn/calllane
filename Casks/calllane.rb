# Copy into rav4nn/homebrew-tap/Casks/ after each release and fill in sha256 from the release notes.
cask "calllane" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256_FROM_RELEASE"

  url "https://github.com/rav4nn/calllane/releases/download/v#{version}/CallLane.zip"
  name "CallLane"
  desc "Menu bar app that stops macOS call audio ducking with a Calls output device"
  homepage "https://github.com/rav4nn/calllane"

  depends_on macos: ">= :sonoma"

  app "CallLane.app"

  caveats <<~EOS
    CallLane is signed ad-hoc. Install with --no-quarantine, or allow it under
    System Settings → Privacy & Security after the first launch.
  EOS

  zap trash: [
    "~/Library/Preferences/dev.rav4nn.calllane.plist",
  ]
end
