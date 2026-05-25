import SwiftUI
import UserNotifications

/// Settings section embedded in the My Soul tab. Three sections:
/// 1. Reminder schedule (multi-time picker)
/// 2. Pair status (connected Mac or "not paired" placeholder)
/// 3. Privacy footer (static text)
struct SettingsView: View {
    @Binding var flow: PairingFlow
    @State private var reminderTimes: [Date] = []
    @State private var showingTimePicker = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var showPairingSheet = false
    @State private var connectMacFlow = PairingFlow()

    private let defaultReminders: [Date] = {
        let calendar = Calendar.current
        let now = Date()
        return [
            calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)!,
            calendar.date(bySettingHour: 13, minute: 0, second: 0, of: now)!,
            calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now)!
        ]
    }()

    var body: some View {
        Form {
            Section {
                if reminderTimes.isEmpty {
                    Text("No reminders set")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(reminderTimes.indices, id: \.self) { idx in
                        HStack {
                            Text(timeFormatter.string(from: reminderTimes[idx]))
                            Spacer()
                            Button(role: .destructive) {
                                reminderTimes.remove(at: idx)
                                saveReminders()
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    showingTimePicker = true
                } label: {
                    Label("Add reminder", systemImage: "plus.circle")
                }
            } header: {
                Text("Reminders")
            } footer: {
                if notificationStatus == .denied {
                    Text("Notifications: denied — enable in iOS Settings to receive reminders.")
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.85))
                } else {
                    Text("Choose times when you want to be reminded to check in.")
                        .font(.caption2)
                }
            }

            Section("Pair status") {
                if case .paired(let name) = flow.state {
                    HStack {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Connected to \(name)")
                    }
                } else if case .connecting(let name) = flow.state {
                    HStack {
                        Circle()
                            .fill(.yellow)
                            .frame(width: 8, height: 8)
                        Text("Connecting to \(name)...")
                    }
                } else if case .authenticating(let name) = flow.state {
                    HStack {
                        Circle()
                            .fill(.yellow)
                            .frame(width: 8, height: 8)
                        Text("Authenticating with \(name)...")
                    }
                } else if case .measuring(let name, _, _) = flow.state {
                    HStack {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Measuring with \(name)")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Not paired")
                            .foregroundStyle(.secondary)
                        Button("Connect a Mac") {
                            connectMacFlow = PairingFlow()
                            showPairingSheet = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Section {
                Text("No data leaves this phone. Mac pairing uses your local network only. We don't run servers.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Privacy")
            }
        }
        .sheet(isPresented: $showingTimePicker) {
            timePickerSheet
        }
        .sheet(isPresented: $showPairingSheet) {
            PairingSheetView(
                flow: $connectMacFlow,
                onPaired: { showPairingSheet = false },
                onSkipped: { showPairingSheet = false }
            )
        }
        .onAppear {
            loadReminders()
            Task {
                notificationStatus = await ReminderScheduler.shared.authorizationStatus()
            }
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
                    Button("Cancel") {
                        showingTimePicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }

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
        let isoStrings = reminderTimes.map { iso.string(from: $0) }
        guard let data = try? JSONEncoder().encode(isoStrings) else { return }
        UserDefaults.standard.set(data, forKey: "niyora.reminders.schedule")

        let comps = reminderTimes.map {
            Calendar.current.dateComponents([.hour, .minute], from: $0)
        }
        Task {
            await ReminderScheduler.shared.schedule(times: comps)
            notificationStatus = await ReminderScheduler.shared.authorizationStatus()
        }
    }
}
