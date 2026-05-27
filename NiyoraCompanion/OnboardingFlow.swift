import SwiftUI

/// 3-step first-launch onboarding shown once, gated by
/// `niyora.onboarding.completed` in UserDefaults.
///
/// Trust (step 0) -> Pair or Continue (step 1) -> Reminders (step 2)
/// -> Breath home.
struct OnboardingFlow: View {
    let onComplete: () -> Void

    @State private var step = 0
    @State private var pairingFlow = PairingFlow()

    var body: some View {
        switch step {
        case 0:
            TrustStep(onContinue: { step = 1 })
        case 1:
            PairStep(flow: $pairingFlow, onNext: { step = 2 })
        default:
            RemindersStep(onDone: onComplete)
        }
    }
}

// MARK: - Step 0: Trust

private struct TrustStep: View {
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            onboardingGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.7), lineWidth: 1.2)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .fill(Color.white.opacity(0.85))
                                    .frame(width: 4, height: 4)
                            )
                        Text("Niyora")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }

                    Text("Your calm companion")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(0.3)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 28) {
                    trustRow(icon: "iphone", text: "Everything stays on your device")
                    trustRow(icon: "lock.shield", text: "No accounts, no servers, no cloud")
                    trustRow(icon: "network", text: "Mac pairing uses your local network only")
                }
                .padding(.horizontal, 40)

                Spacer()

                violetButton(label: "Continue", action: onContinue)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 48)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func trustRow(icon: String, text: String) -> some View {
        HStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 28)
            Text(text)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

// MARK: - Step 1: Pair or Continue

private struct PairStep: View {
    @Binding var flow: PairingFlow
    let onNext: () -> Void

    var body: some View {
        PairingSheetView(
            flow: $flow,
            onPaired: onNext,
            onSkipped: onNext
        )
    }
}

// MARK: - Shared pairing view

/// Presents QR scan and "Continue without a Mac" options.
/// Shared between onboarding step 1 and the Settings "Connect a Mac" button.
struct PairingSheetView: View {
    @Binding var flow: PairingFlow
    let onPaired: () -> Void
    let onSkipped: () -> Void

    @State private var showScanner = false
    @State private var scanError: String?

    var body: some View {
        ZStack {
            onboardingGradient.ignoresSafeArea()

            if showScanner {
                scannerOverlay
            } else {
                mainContent
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: flow.state) { _, newState in
            if case .paired(_) = newState { onPaired() }
            else if case .skipped = newState { onSkipped() }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                Image(systemName: "laptopcomputer.and.iphone")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.7))

                Text("Connect your Mac")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Open Niyora on your Mac, then scan the QR code it shows.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            connectionStatus

            VStack(spacing: 14) {
                Button {
                    showScanner = true
                    scanError = nil
                } label: {
                    Label("Scan QR on Mac", systemImage: "qrcode.viewfinder")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(violetGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    flow.skip()
                } label: {
                    Text("Continue without a Mac")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        if case .connecting(_) = flow.state {
            ProgressView()
                .tint(.white)
                .padding(.bottom, 20)
        } else if case .authenticating(_) = flow.state {
            ProgressView()
                .tint(.white)
                .padding(.bottom, 20)
        } else if case .failed(let reason) = flow.state {
            Text(reason)
                .font(.footnote)
                .foregroundStyle(.red.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
        } else if let err = scanError {
            Text(err)
                .font(.footnote)
                .foregroundStyle(.red.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
        }
    }

    private var scannerOverlay: some View {
        ZStack(alignment: .bottom) {
            QRScannerView(
                onCode: { raw in
                    showScanner = false
                    guard let payload = QrPayload.decode(raw) else {
                        scanError = "QR code not recognised. Make sure Niyora is open on your Mac."
                        return
                    }
                    scanError = nil
                    flow.pair(with: payload)
                },
                onStatusChange: { status in
                    switch status {
                    case .denied:
                        showScanner = false
                        scanError = "Camera access needed to scan the QR. Allow it under Settings."
                    case .unsupported:
                        showScanner = false
                        scanError = "QR scanning is not available on this device."
                    case .ready:
                        break
                    }
                }
            )
            .ignoresSafeArea()

            Button("Cancel") {
                showScanner = false
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.black.opacity(0.55))
        }
    }
}

// MARK: - Step 2: Reminders

private struct RemindersStep: View {
    let onDone: () -> Void

    @State private var times: [Date]
    @State private var showingTimePicker = false

    init(onDone: @escaping () -> Void) {
        self.onDone = onDone
        let cal = Calendar.current
        let now = Date()
        _times = State(initialValue: [
            cal.date(bySettingHour: 9, minute: 0, second: 0, of: now)!,
            cal.date(bySettingHour: 13, minute: 0, second: 0, of: now)!,
            cal.date(bySettingHour: 17, minute: 0, second: 0, of: now)!,
        ])
    }

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ZStack {
            onboardingGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 44, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.7))

                    Text("Check-in reminders")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Change these any time in My Soul.")
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer(minLength: 32)

                timeList

                Spacer()

                violetButton(label: "Done") {
                    persistTimes()
                    let comps = times.map {
                        Calendar.current.dateComponents([.hour, .minute], from: $0)
                    }
                    Task {
                        await ReminderScheduler.shared.schedule(times: comps)
                        onDone()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingTimePicker) {
            timePickerSheet
        }
    }

    private var timeList: some View {
        VStack(spacing: 0) {
            ForEach(times.indices, id: \.self) { i in
                HStack {
                    Text(timeFormatter.string(from: times[i]))
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    Button(role: .destructive) {
                        times.remove(at: i)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                Divider()
                    .background(Color.white.opacity(0.12))
                    .padding(.horizontal, 20)
            }

            Button {
                showingTimePicker = true
            } label: {
                Label("Add time", systemImage: "plus.circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 24)
    }

    private var timePickerSheet: some View {
        NavigationStack {
            DatePicker(
                "Select time",
                selection: Binding(
                    get: { Date() },
                    set: { newTime in
                        times.append(newTime)
                        times.sort()
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

    private func persistTimes() {
        let iso = ISO8601DateFormatter()
        let isoStrings = times.map { iso.string(from: $0) }
        guard let data = try? JSONEncoder().encode(isoStrings) else { return }
        UserDefaults.standard.set(data, forKey: "niyora.reminders.schedule")
    }
}

// MARK: - Shared helpers

private func violetButton(label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(label)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(violetGradient)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
    .buttonStyle(.plain)
}

private let violetGradient = LinearGradient(
    colors: [
        Color(hue: 270.0 / 360.0, saturation: 0.55, brightness: 0.55),
        Color(hue: 280.0 / 360.0, saturation: 0.50, brightness: 0.45),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

private let onboardingGradient = LinearGradient(
    colors: [
        Color(hue: 280.0 / 360.0, saturation: 0.25, brightness: 0.05),
        Color(hue: 270.0 / 360.0, saturation: 0.20, brightness: 0.02),
        Color.black,
    ],
    startPoint: .top,
    endPoint: .bottom
)
