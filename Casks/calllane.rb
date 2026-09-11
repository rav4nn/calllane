# Copy into rav4nn/homebrew-tap/Casks/ after each release and fill in sha256 from the release notes.
cask "calllane" do
  version "0.1.0"
  sha256 "293f41fd933c3019380dcecb83e67764a686665223c3ab2339d4fda21c916085"

  url "https://github.com/rav4nn/calllane/releases/download/v#{version}/CallLane.zip"
  name "CallLane"
  desc "Menu bar app that stops call audio ducking with a Calls output device"
  homepage "https://github.com/rav4nn/calllane"

  depends_on macos: :sonoma

  app "CallLane.app"

  zap trash: "~/Library/Preferences/dev.rav4nn.calllane.plist"

  caveats <<~EOS
    CallLane is signed ad-hoc. Clear the quarantine flag before the first launch:
      xattr -dr com.apple.quarantine /Applications/CallLane.app
    or allow the app under System Settings → Privacy & Security after it is blocked.
  EOS
end
