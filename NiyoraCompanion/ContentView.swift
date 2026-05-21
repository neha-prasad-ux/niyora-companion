import SwiftUI

/// The primary screen of Niyora Companion. Three states:
///
/// 1. No Mac paired yet: introduction + a single "Connect to Mac" button
///    that opens the QR scanner.
/// 2. At least one Mac paired: paired status, last received request, and
///    a small footer about how measurements work.
/// 3. Scanning: full-screen camera preview with a cancel chip.
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
    @State private var measurementController: MeasurementController?

    var body: some View {
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
        .fullScreenCover(isPresented: $showingScanner) {
            scannerSheet
        }
        .fullScreenCover(item: $flow.pendingRequest) { request in
            measurementSheet(for: request)
        }
        .onAppear {
            // Auto-reconnect to the first known Mac on launch. Real
            // mDNS-based discovery for IP changes comes in a later
            // milestone if it proves necessary.
            if case .idle = flow.state, let first = KnownServerStore.all().first {
                flow.reconnect(to: first)
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
                Text("Keep the app open to receive measurement requests. We turn on the camera and flashlight only while you're actively measuring.")
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

    @ViewBuilder
    private func measurementSheet(for request: PairingFlow.PendingRequest) -> some View {
        let controller = makeOrReuseController(for: request)
        MeasurementSheet(
            controller: controller,
            onCancel: {
                controller.cancel()
                flow.clearPendingRequest()
                measurementController = nil
            },
            onRetry: {
                let fresh = MeasurementController(
                    sessionId: request.sessionId,
                    phase: request.phase,
                    techniqueName: request.techniqueName
                )
                measurementController = fresh
                Task { await fresh.start() }
            },
            onDone: {
                Task {
                    if case let .finished(result) = controller.state {
                        await flow.sendResult(
                            sessionId: request.sessionId,
                            phase: request.phase,
                            result: result
                        )
                    } else {
                        flow.clearPendingRequest()
                    }
                    measurementController = nil
                }
            }
        )
        .onAppear {
            if case .idle = controller.state {
                Task { await controller.start() }
            }
        }
    }

    private func makeOrReuseController(for request: PairingFlow.PendingRequest) -> MeasurementController {
        if let existing = measurementController,
           existing.sessionId == request.sessionId,
           existing.phase == request.phase {
            return existing
        }
        let fresh = MeasurementController(
            sessionId: request.sessionId,
            phase: request.phase,
            techniqueName: request.techniqueName
        )
        measurementController = fresh
        return fresh
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
