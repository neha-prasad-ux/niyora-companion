import SwiftUI

/// The primary screen of Niyora Companion. Two tabs:
///
/// 1. Home: Three states:
///    - No Mac paired yet: introduction + a single "Connect to Mac" button
///      that opens the QR scanner.
///    - At least one Mac paired: paired status, last received request, and
///      a small footer about how measurements work.
///    - Scanning: full-screen camera preview with a cancel chip.
/// 2. My Soul: Tier progression, session history, and settings.
///
/// When the Mac sends a `request_measurement` frame, `MeasurementSheet`
/// presents over the whole view to drive a 30s PPG capture.
///
/// The original HealthKit spike (M1-2) lives behind a DEBUG-only
/// toolbar button. It is no longer part of the shipping data path · PPG
/// is the source now · but the spike helped de-risk the early HealthKit
/// work and is useful for diagnosing Watch HRV in isolation.
struct ContentView: View {
    @State private var flow = PairingFlow()
    @State private var showingScanner = false
    @State private var scannerStatus: QRScannerView.Status = .ready
    @State private var lastScanError: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            homeTab
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            MySoulTabView(flow: $flow)
                .tabItem {
                    Label("My Soul", systemImage: "sparkles")
                }
        }
        .fullScreenCover(isPresented: $showingScanner) {
            scannerSheet
        }
        .fullScreenCover(item: $flow.pendingRequest) { request in
            measurementSheet(for: request)
        }
        .onAppear {
            // First-launch and view-mount auto-reconnect to the first
            // known Mac. The scene-phase handler below covers the
            // foreground-from-background case.
            if case .idle = flow.state, let first = KnownServerStore.all().first {
                flow.reconnect(to: first)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // iOS kills the TCP socket while we're backgrounded · plain
            // TCP doesn't get any background exceptions. Every time the
            // user brings us back to .active we re-establish the link
            // so they don't have to think about it. If the connection
            // is still alive (rare but possible on quick app-switches)
            // the existing flow is left in place.
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

    private var homeTab: some View {
        NavigationStack {
            mainContent
                .navigationTitle("Niyora Companion")
                .toolbar {
                    #if DEBUG
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            HRVSpikeView()
                        } label: {
                            Image(systemName: "waveform.path.ecg")
                        }
                    }
                    #endif
                }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var mainContent: some View {
        // Touch flow.state so the @Observable dependency is registered
        // on this view. Without this, a fresh scan completes the wire
        // handshake (Mac flips to paired, KnownServerStore is upserted)
        // but introState stays on screen, because KnownServerStore.all()
        // is a plain UserDefaults read that doesn't trigger SwiftUI.
        let _ = flow.state
        let known = KnownServerStore.all()
        if known.isEmpty {
            introState
        } else {
            pairedState(known: known)
        }
    }

    private var introState: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(.tint)
                    .padding(.top, 24)

                VStack(spacing: 8) {
                    Text("Connect to your Mac")
                        .font(.title2.weight(.semibold))
                    Text("Niyora on your Mac will ask this app for a 30 second stress estimate when you tap Measure stress. Hold your fingertip on the back camera and flashlight, that's it. Nothing leaves your devices.")
                        .multilineTextAlignment(.center)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                }

                Button {
                    lastScanError = nil
                    showingScanner = true
                } label: {
                    Label("Connect to Mac", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)

                if let err = lastScanError {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 32)
                        .multilineTextAlignment(.center)
                }

                Spacer(minLength: 16)
            }
        }
    }

    private func pairedState(known: [KnownServer]) -> some View {
        Form {
            Section {
                Button {
                    flow.startStandaloneMeasurement()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Measure stress")
                                .font(.headline)
                            Text("30 second reading from your camera")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Section("Paired Macs") {
                ForEach(known) { server in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                            Text(server.serverName)
                                .font(.body.weight(.medium))
                            Spacer()
                            Button("Unpair", role: .destructive) {
                                KeychainStore.deleteSecret(forServerId: server.serverId)
                                KnownServerStore.remove(serverId: server.serverId)
                                LocalMeasurementStore.clear()
                                LocalSessionStore.clear()
                                flow.disconnect()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        Text(stateDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Button {
                    lastScanError = nil
                    showingScanner = true
                } label: {
                    Label("Pair another Mac", systemImage: "qrcode.viewfinder")
                }
            }

            Section {
                Text("Take a reading anytime by tapping Measure stress, or wait for your Mac to ask. Camera and flashlight are only on while you're measuring.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Measurements stay on your iPhone and Mac. They are never uploaded.")
                    .font(.caption2)
            }
        }
    }

    private var statusColor: Color {
        switch flow.state {
        case .paired, .measuring: return .green
        case .authenticating, .connecting: return .yellow
        case .failed: return .red
        case .idle: return .gray
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
        // The sheet owns its `MeasurementController` lifecycle · we
        // only react to the two terminal outcomes here. See
        // `MeasurementSheet` for why ownership lives there.
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
