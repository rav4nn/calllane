import SwiftUI

struct SetupView: View {
    private let apps: [(String, String)] = [
        ("FaceTime", "Menu bar → Video → Output → Calls"),
        ("Zoom", "Settings → Audio → Speaker → Calls"),
        ("Google Meet (Chrome)", "In a call: speaker menu in the bottom bar → Calls. Or ⋮ → Settings → Audio → Speakers"),
        ("Slack", "Preferences → Audio & video → Speaker → Calls"),
        ("Microsoft Teams", "Settings → Devices → Speaker → Calls"),
        ("Discord", "User Settings → Voice & Video → Output Device → Calls"),
        ("WhatsApp", "Settings → Calls → Speaker → Calls"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set “Calls” as the speaker in each call app").font(.headline)
            Text("Do this once per app. Keep the microphone on your Mac’s built-in mic or a USB mic, not the AirPods mic. Keep your headphones as the system output; CallLane reverts it if “Calls” is picked there.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(apps, id: \.0) { app in
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.0).font(.subheadline).bold()
                    Text(app.1).font(.callout).foregroundStyle(.secondary)
                }
            }
            Text("Safari has no per-site speaker picker, so calls in Safari cannot use Calls.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 420)
    }
}
