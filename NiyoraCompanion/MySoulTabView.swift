import SwiftUI

/// My Soul screen: presented full-screen from the home view's profile
/// icon. Shows the current Soul tier as a 3D orb (matching the home
/// view's rose orb language but coloured per tier) with Saturn-style
/// rings per tier count, plus tier name, progression, session history,
/// reminder schedule, pair status, and privacy footer per the v1 spec
/// (niyora-companion#34).
struct MySoulTabView: View {
    @Binding var flow: PairingFlow
    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [LocalSessionStore.Session] = []
    @State private var currentTier: Tier = .spark
    @State private var reminderTimes: [Date] = []
    @State private var showingTimePicker = false

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                ScrollView {
                    VStack(spacing: 0) {
                        Text("My Soul")
                            .font(.system(size: 32, weight: .light, design: .serif))
                            .foregroundStyle(.white)
                            .padding(.top, 24)
                            .padding(.bottom, 32)

                        tierOrb

                        tierLabel
                            .padding(.top, 16)
                            .padding(.bottom, 48)

                        if !recentSessions.isEmpty {
                            sessionsSection
                                .padding(.bottom, 40)
                        }

                        remindersSection
                            .padding(.bottom, 40)

                        pairSection
                            .padding(.bottom, 40)

                        privacyFooter
                            .padding(.bottom, 48)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
        .onAppear { loadData() }
        .sheet(isPresented: $showingTimePicker) {
            timePickerSheet
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 44, height: 44)

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 1.2)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 4, height: 4)
                    )
                Text("My Soul")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Tier orb (3D, coloured per tier, with Saturn rings)

    private var tierOrb: some View {
        let core: CGFloat = 240
        let halo: CGFloat = core * 1.05
        let accent = currentTier.color
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accent.opacity(0.30), accent.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: halo * 0.55
                    )
                )
                .frame(width: halo, height: halo)
                .blur(radius: 6)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            accent.opacity(0.95),
                            accent.opacity(0.55),
                            accent.opacity(0.15),
                        ],
                        center: UnitPoint(x: 0.35, y: 0.30),
                        startRadius: 4,
                        endRadius: core * 0.6
                    )
                )
                .frame(width: core, height: core)
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.15), lineWidth: 1)
                )

            ForEach(0..<ringCount, id: \.self) { i in
                Ellipse()
                    .stroke(accent.opacity(0.55 - Double(i) * 0.08), lineWidth: 1.4)
                    .frame(
                        width: core + CGFloat(i * 18) + 28,
                        height: 28 + CGFloat(i * 4)
                    )
                    .shadow(color: accent.opacity(0.20), radius: 6)
            }
        }
    }

    private var ringCount: Int {
        switch currentTier {
        case .spark:      return 0
        case .glow:       return 1
        case .shine:      return 2
        case .radiance:   return 3
        case .brilliance: return 4
        }
    }

    // MARK: - Tier label

    private var tierLabel: some View {
        VStack(spacing: 8) {
            Text(currentTier.name)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(currentTier.color)

            Text("\(completedCount) session\(completedCount == 1 ? "" : "s")")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(.white.opacity(0.5))

            if let remaining = currentTier.sessionsToNext(currentCount: completedCount),
               let next = Tier(rawValue: currentTier.rawValue + 1) {
                Text("\(remaining) more to \(next.name)")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 6)
            } else {
                Text("Maximum tier reached")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 6)
            }
        }
    }

    // MARK: - Session history

    private var recentSessions: [LocalSessionStore.Session] {
        Array(sessions.filter(\.completed).prefix(20))
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Recent sessions")
                .padding(.bottom, 12)

            ForEach(recentSessions) { session in
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.techniqueName)
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(.white.opacity(0.85))
                            Text(relativeTime(session.timestamp))
                                .font(.system(size: 12, weight: .light))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        Spacer()
                        Text(durationLabel(session.duration))
                            .font(.system(size: 13, weight: .light))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)

                    if session.id != recentSessions.last?.id {
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 1)
                            .padding(.horizontal, 20)
                    }
                }
            }
        }
    }

    // MARK: - Reminders

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Reminders")
                .padding(.bottom, 12)

            if reminderTimes.isEmpty {
                Text("No reminders set")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            } else {
                ForEach(reminderTimes.indices, id: \.self) { idx in
                    VStack(spacing: 0) {
                        HStack {
                            Text(timeFormatter.string(from: reminderTimes[idx]))
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(.white.opacity(0.85))
                            Spacer()
                            Button {
                                reminderTimes.remove(at: idx)
                                saveReminders()
                            } label: {
                                Image(systemName: "minus.circle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)

                        if idx < reminderTimes.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.07))
                                .frame(height: 1)
                                .padding(.horizontal, 20)
                        }
                    }
                }
            }

            Button {
                showingTimePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 15))
                    Text("Add reminder")
                        .font(.system(size: 15, weight: .regular))
                }
                .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 10)
        }
    }

    private var timePickerSheet: some View {
        NavigationStack {
            DatePicker(
                "Select time",
                selection: Binding(
                    get: { Date() },
                    set: { newTime in
                        reminderTimes.append(newTime)
                        reminderTimes.sort()
                        saveReminders()
                        showingTimePicker = false
                    }
                ),
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .padding()
            .navigationTitle("Add reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingTimePicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Pair status

    private var pairSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Mac")
                .padding(.bottom, 12)

            HStack(spacing: 10) {
                pairDot
                pairLabel
                Spacer()
                pairAction
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder private var pairDot: some View {
        if case .paired = flow.state {
            Circle().fill(Color(hue: 130.0 / 360.0, saturation: 0.6, brightness: 0.75))
                .frame(width: 8, height: 8)
        } else if case .measuring = flow.state {
            Circle().fill(Color(hue: 130.0 / 360.0, saturation: 0.6, brightness: 0.75))
                .frame(width: 8, height: 8)
        } else if case .connecting = flow.state {
            Circle().fill(Color(hue: 50.0 / 360.0, saturation: 0.7, brightness: 0.85))
                .frame(width: 8, height: 8)
        } else if case .authenticating = flow.state {
            Circle().fill(Color(hue: 50.0 / 360.0, saturation: 0.7, brightness: 0.85))
                .frame(width: 8, height: 8)
        } else {
            Circle().fill(Color.white.opacity(0.25))
                .frame(width: 8, height: 8)
        }
    }

    @ViewBuilder private var pairLabel: some View {
        if case .paired(let name) = flow.state {
            Text("Connected to \(name)")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))
        } else if case .measuring(let name, _, _) = flow.state {
            Text("Connected to \(name)")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))
        } else if case .connecting(let name) = flow.state {
            Text("Connecting to \(name)...")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(.white.opacity(0.6))
        } else if case .authenticating(let name) = flow.state {
            Text("Authenticating with \(name)...")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(.white.opacity(0.6))
        } else if case .failed(let reason) = flow.state {
            Text(reason)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(2)
        } else {
            Text("Not paired")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    @ViewBuilder private var pairAction: some View {
        if case .paired = flow.state {
            Button("Disconnect") { flow.disconnect() }
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.45))
                .buttonStyle(.plain)
        } else if case .measuring = flow.state {
            Button("Disconnect") { flow.disconnect() }
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.45))
                .buttonStyle(.plain)
        } else if case .idle = flow.state {
            Button("Connect a Mac") { }
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.6))
                .buttonStyle(.plain)
        } else if case .failed = flow.state {
            Button("Connect a Mac") { }
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.6))
                .buttonStyle(.plain)
        }
    }

    // MARK: - Privacy footer

    private var privacyFooter: some View {
        Text("No data leaves this phone. Mac pairing uses your local network only. We don't run servers.")
            .font(.system(size: 12, weight: .light))
            .foregroundStyle(.white.opacity(0.45))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
    }

    // MARK: - Helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.35))
            .tracking(1.2)
            .textCase(.uppercase)
            .padding(.horizontal, 20)
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "Just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min\(minutes == 1 ? "" : "s") ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) hour\(hours == 1 ? "" : "s") ago" }
        let days = hours / 24
        return "\(days) day\(days == 1 ? "" : "s") ago"
    }

    private func durationLabel(_ duration: TimeInterval) -> String {
        let s = Int(duration)
        if s < 60 { return "\(s)s" }
        let m = s / 60
        let r = s % 60
        return r == 0 ? "\(m)m" : "\(m)m \(r)s"
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }

    // MARK: - Reminders persistence

    private let defaultReminders: [Date] = {
        let cal = Calendar.current
        let now = Date()
        return [
            cal.date(bySettingHour: 9, minute: 0, second: 0, of: now)!,
            cal.date(bySettingHour: 13, minute: 0, second: 0, of: now)!,
            cal.date(bySettingHour: 17, minute: 0, second: 0, of: now)!,
        ]
    }()

    private func loadReminders() {
        guard let data = UserDefaults.standard.data(forKey: "niyora.reminders.schedule"),
              let isoStrings = try? JSONDecoder().decode([String].self, from: data)
        else {
            reminderTimes = defaultReminders
            saveReminders()
            return
        }
        let iso = ISO8601DateFormatter()
        reminderTimes = isoStrings.compactMap { iso.date(from: $0) }
        if reminderTimes.isEmpty {
            reminderTimes = defaultReminders
            saveReminders()
        }
    }

    private func saveReminders() {
        let iso = ISO8601DateFormatter()
        let strings = reminderTimes.map { iso.string(from: $0) }
        guard let data = try? JSONEncoder().encode(strings) else { return }
        UserDefaults.standard.set(data, forKey: "niyora.reminders.schedule")
    }

    // MARK: - Computed

    private var completedCount: Int {
        sessions.filter(\.completed).count
    }

    // MARK: - Data

    private func loadData() {
        sessions = LocalSessionStore.all()
        currentTier = Tier.forSessionCount(completedCount)
        loadReminders()
    }
}

private let backgroundGradient = LinearGradient(
    colors: [
        Color(hue: 280.0 / 360.0, saturation: 0.25, brightness: 0.05),
        Color(hue: 270.0 / 360.0, saturation: 0.20, brightness: 0.02),
        Color.black,
    ],
    startPoint: .top,
    endPoint: .bottom
)

#Preview {
    MySoulTabView(flow: .constant(PairingFlow()))
}
