import SwiftUI

/// The primary screen of Niyora Companion. Three states:
///
/// 1. No Mac paired yet: introduction + a single "Connect to Mac" button
///    that opens the QR scanner.
/// 2. At least one Mac paired: a hero "Measure stress" action with the
///    paired-Mac status sitting at the bottom of the screen.
/// 3. Scanning: full-screen camera preview with a cancel chip.
///
/// The layout matches the rest of the product · the same near-black
/// indigo backdrop and soft orb glow as `MeasurementSheet`, a serif
/// wordmark at the top, and the whole screen owned by the app rather
/// than a settings-style Form. When the Mac sends a `request_measurement`
/// frame, `MeasurementSheet` presents over the whole view to drive a 30s
/// PPG capture.
///
/// The original HealthKit spike (M1-2) lives behind a DEBUG-only toolbar
/// button. It is no longer part of the shipping data path · PPG is the
/// source now · but the spike helped de-risk the early HealthKit work
/// and is useful for diagnosing Watch HRV in isolation.
struct ContentView: View {
    @State private var flow = PairingFlow()
    @State private var showingScanner = false
    @State private var showingHRVSpike = false
    @State private var scannerStatus: QRScannerView.Status = .ready
    @State private var lastScanError: String?
    @State private var orbPulse = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            mainContent

            #if DEBUG
            Button {
                showingHRVSpike = true
            } label: {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(10)
                    .background(.white.opacity(0.06), in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.08), lineWidth: 1))
            }
            .padding(.trailing, 20)
            .padding(.top, 8)
            #endif
        }
        .background(niyoraBackdrop.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showingScanner) {
            scannerSheet
        }
        .fullScreenCover(item: $flow.pendingRequest) { request in
            measurementSheet(for: request)
        }
        #if DEBUG
        .sheet(isPresented: $showingHRVSpike) {
            NavigationStack { HRVSpikeView() }
        }
        #endif
        .onAppear {
            if case .idle = flow.state, let first = KnownServerStore.all().first {
                flow.reconnect(to: first)
            }
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    orbPulse = true
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // iOS kills the TCP socket while we're backgrounded · plain
            // TCP doesn't get any background exceptions. Every time the
            // user brings us back to .active we re-establish the link so
            // they don't have to think about it.
            guard phase == .active else { return }
            guard let first = KnownServerStore.all().first else { return }
            switch flow.state {
            case .idle, .failed:
                flow.reconnect(to: first)
            case .connecting, .authenticating, .paired, .measuring:
                break
            }
        }
    }

    // MARK: - Backdrop

    /// Same indigo gradient as the breathing canvas and measurement
    /// sheet. The home screen sits in the same visual world as the rest
    /// of the product.
    private var niyoraBackdrop: some View {
        ZStack {
            Color(red: 0.04, green: 0.035, blue: 0.075)
            RadialGradient(
                colors: [Color(hue: 0.70, saturation: 0.5, brightness: 0.35, opacity: 0.65), .clear],
                center: UnitPoint(x: 0.5, y: 0.28),
                startRadius: 0,
                endRadius: 360
            )
            RadialGradient(
                colors: [Color(hue: 0.74, saturation: 0.5, brightness: 0.22, opacity: 0.55), .clear],
                center: UnitPoint(x: 0.5, y: 0.95),
                startRadius: 0,
                endRadius: 380
            )
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private var mainContent: some View {
        // Touch flow.state so the @Observable dependency is registered
        // on this view. Without this, a fresh scan completes the wire
        // handshake (Mac flips to paired, KnownServerStore is upserted)
        // but introState stays on screen, because KnownServerStore.all()
        // is a plain UserDefaults read that doesn't trigger SwiftUI.
        let _ = flow.state
        let known = KnownServerStore.all()
        #if DEBUG
        let mock = ProcessInfo.processInfo.arguments.contains("--niyora-fake-paired")
        if mock {
            pairedState(known: [KnownServer(serverId: "demo", serverName: "Neha's MacBook Air", host: "10.0.0.1", port: 9999)])
        } else if known.isEmpty {
            introState
        } else {
            pairedState(known: known)
        }
        #else
        if known.isEmpty {
            introState
        } else {
            pairedState(known: known)
        }
        #endif
    }

    // MARK: - Intro state

    private var introState: some View {
        VStack(spacing: 0) {
            wordmark
                .padding(.horizontal, 28)
                .padding(.top, 4)

            Spacer(minLength: 8)

            ZStack {
                orb(hue: 0.78, opacity: 0.55, size: 240)
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 52, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer(minLength: 12)

            VStack(spacing: 12) {
                Text("Pair with Niyora on your Mac")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(.white.opacity(0.95))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Niyora will ask for a 30 second stress reading when you tap Measure stress on the Mac. Hold your fingertip on the back camera. Nothing leaves your devices.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 16)

            VStack(spacing: 10) {
                Button {
                    lastScanError = nil
                    showingScanner = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 16, weight: .medium))
                        Text("Connect to Mac")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.10), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                }

                if let err = lastScanError {
                    Text(err)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.6))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Paired state

    private func pairedState(known: [KnownServer]) -> some View {
        VStack(spacing: 0) {
            wordmark
                .padding(.horizontal, 28)
                .padding(.top, 4)

            Spacer(minLength: 12)

            measureHero

            Spacer(minLength: 12)

            VStack(spacing: 10) {
                ForEach(known) { server in
                    statusCard(for: server)
                }

                Button {
                    lastScanError = nil
                    showingScanner = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 12))
                        Text("Pair another Mac")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 8)
        }
    }

    private var measureHero: some View {
        VStack(spacing: 18) {
            Button {
                flow.startStandaloneMeasurement()
            } label: {
                ZStack {
                    orb(hue: 0.95, opacity: 0.55, size: 260)
                        .scaleEffect(orbPulse ? 1.04 : 0.96)

                    Circle()
                        .fill(.white.opacity(0.06))
                        .overlay(Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1))
                        .frame(width: 152, height: 152)

                    VStack(spacing: 8) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        Color(red: 1.0, green: 0.55, blue: 0.65),
                                        Color(red: 0.95, green: 0.35, blue: 0.5),
                                    ],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                        Text("Measure")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Measure stress")
            .accessibilityHint("Starts a 30 second reading from your camera.")

            VStack(spacing: 4) {
                Text("Measure stress")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(.white.opacity(0.95))
                Text("30 second reading from your camera")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private func statusCard(for server: KnownServer) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(server.serverName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(stateDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                KeychainStore.deleteSecret(forServerId: server.serverId)
                KnownServerStore.remove(serverId: server.serverId)
                LocalMeasurementStore.clear()
                flow.disconnect()
            } label: {
                Text("Unpair")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.6))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.05), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Shared visuals

    private var wordmark: some View {
        HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text("Niyora")
                .font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundStyle(.white.opacity(0.95))
            Text("COMPANION")
                .font(.system(size: 10, weight: .medium))
                .tracking(2.5)
                .foregroundStyle(.white.opacity(0.4))
                .padding(.bottom, 4)
            Spacer()
        }
    }

    private func orb(hue: Double, opacity: Double, size: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(hue: hue, saturation: 0.6, brightness: 0.55, opacity: opacity),
                        Color(hue: hue, saturation: 0.6, brightness: 0.4, opacity: 0),
                    ],
                    center: .center,
                    startRadius: 4,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .blur(radius: 6)
    }

    private var statusColor: Color {
        switch flow.state {
        case .paired, .measuring: return Color(red: 0.4, green: 0.85, blue: 0.55)
        case .authenticating, .connecting: return Color(red: 0.95, green: 0.8, blue: 0.35)
        case .failed: return Color(red: 1.0, green: 0.45, blue: 0.5)
        case .idle: return .white.opacity(0.4)
        }
    }

    private var stateDescription: String {
        switch flow.state {
        case .idle: return "Not connected. Tap the Niyora menu bar icon on your Mac to wake it up."
        case .connecting(let name): return "Connecting to \(name)…"
        case .authenticating(let name): return "Authenticating with \(name)…"
        case .paired(let name): return "Connected to \(name). Waiting for measurement requests."
        case .measuring(let name, _, let phase):
            return "Measuring \(phase == .pre ? "before" : "after") · \(name)"
        case .failed(let reason): return reason
        }
    }

    // MARK: - Measurement

    private func measurementSheet(for request: PairingFlow.PendingRequest) -> some View {
        // The sheet owns its `MeasurementController` lifecycle · we only
        // react to the two terminal outcomes here. See `MeasurementSheet`
        // for why ownership lives there.
        MeasurementSheet(
            request: request,
            onCancel: {
                flow.clearPendingRequest()
            },
            onComplete: { result in
                Task {
                    await flow.sendResult(
                        sessionId: request.sessionId,
                        phase: request.phase,
                        result: result
                    )
                }
            }
        )
    }

    // MARK: - Scanner

    private var scannerSheet: some View {
        ZStack(alignment: .topTrailing) {
            QRScannerView { code in
                handleScannedCode(code)
            } onStatusChange: { status in
                scannerStatus = status
            }
            .ignoresSafeArea()

            Button {
                showingScanner = false
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .padding()

            if scannerStatus == .denied {
                deniedOverlay(
                    title: "Camera access denied",
                    body: "Niyora Companion uses the camera to scan the pairing QR on your Mac and to take stress estimates from your fingertip. Enable camera access in Settings → Niyora Companion."
                )
            } else if scannerStatus == .unsupported {
                deniedOverlay(
                    title: "Camera not available",
                    body: "This device cannot scan QR codes. You'll need a working camera to pair."
                )
            }
        }
    }

    private func deniedOverlay(title: String, body: String) -> some View {
        VStack(spacing: 12) {
            Text(title).font(.headline)
            Text(body)
                .multilineTextAlignment(.center)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Close") { showingScanner = false }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.6))
    }

    private func handleScannedCode(_ code: String) {
        guard let payload = QrPayload.decode(code) else {
            lastScanError = "That QR didn't look like a Niyora pairing code."
            showingScanner = false
            return
        }
        showingScanner = false
        flow.pair(with: payload)
    }
}

#Preview {
    ContentView()
}
