import SwiftUI

/// My Soul tab: displays current tier, tier progression, recent sessions,
/// and embedded settings (reminders, pair status, privacy). The visual
/// identity shifts per tier via hue/saturation changes.
struct MySoulTabView: View {
    @Binding var flow: PairingFlow
    @State private var sessions: [LocalSessionStore.Session] = []
    @State private var currentTier: Tier = .spark

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    tierCard
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section("Recent sessions") {
                    if sessions.isEmpty {
                        Text("No sessions yet. Tap Measure stress to start.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(sessions.prefix(10)) { session in
                            sessionRow(session)
                        }
                    }
                }

                Section("Settings") {
                    SettingsView(flow: $flow)
                }
            }
            .navigationTitle("My Soul")
            .onAppear {
                loadData()
            }
        }
    }

    private var tierCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                currentTier.color.opacity(0.3),
                                currentTier.color.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "sparkles")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(currentTier.color)
            }

            VStack(spacing: 6) {
                Text(currentTier.name)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(currentTier.color)

                Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let remaining = currentTier.sessionsToNext(currentCount: sessions.count) {
                Text("\(remaining) more session\(remaining == 1 ? "" : "s") to \(nextTierName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Maximum tier reached")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var nextTierName: String {
        guard let next = Tier(rawValue: currentTier.rawValue + 1) else {
            return ""
        }
        return next.name
    }

    private func sessionRow(_ session: LocalSessionStore.Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: session.isStandalone ? "iphone" : "laptopcomputer")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !session.techniqueName.isEmpty {
                    Text(session.techniqueName)
                        .font(.subheadline.weight(.medium))
                } else {
                    Text(session.isStandalone ? "Phone check-in" : "Mac session")
                        .font(.subheadline.weight(.medium))
                }

                Spacer()

                Text(relativeTime(session.completedAtIso))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func loadData() {
        sessions = LocalSessionStore.all()
        currentTier = Tier.forSessionCount(sessions.count)
    }

    private func relativeTime(_ isoString: String) -> String {
        let iso = ISO8601DateFormatter()
        guard let date = iso.date(from: isoString) else {
            return isoString
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
