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
        VStack(alignment: .leading, spacing: 14) {
            Text("Set “Calls” as the speaker in each call app").font(.headline)
            Text("Do this once per app. Keep the microphone on your Mac’s built-in mic or a USB mic, not the AirPods mic. Keep your headphones as the system output; CallLane reverts it if “Calls” is picked there.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(Array(apps.enumerated()), id: \.element.0) { index, app in
                    if index > 0 { Divider() }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.0).font(.subheadline.weight(.semibold))
                        Text(app.1)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))

            Text("Safari has no per-site speaker picker, so calls in Safari cannot use Calls.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 420)
    }
}
