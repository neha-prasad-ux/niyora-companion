import SwiftUI

/// The primary screen of Niyora Companion. Three states:
///
/// 1. No Mac paired yet: introduction + a single "Connect to Mac" button
///    that opens the QR scanner.
/// 2. At least one Mac paired: paired status, last received window, and
///    a small footer reminding the user to keep the app foreground until
///    the M5+M6 background path lands.
/// 3. Scanning: full-screen camera preview with a cancel chip.
///
/// The original HealthKit spike (M1-2) lives on the Debug tab, only
/// visible in DEBUG builds. It's still useful for sanity-checking that
/// the Watch is writing HRV samples before we ship the background path.
struct ContentView: View {
    @State private var flow = PairingFlow()
    @State private var showingScanner = false
    @State private var scannerStatus: QRScannerView.Status = .ready
    @State private var lastScanError: String?

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
        .onAppear {
            // Auto-reconnect to the first known Mac on launch. Real
            // mDNS-based discovery for IP changes comes in M6.
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
                    Text("Niyora on your Mac will send you a session window each time you finish breathing. This app reads your Apple Watch HRV for that window and sends the result back. Nothing leaves your devices.")
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

            if !flow.receivedWindows.isEmpty {
                Section("Received windows") {
                    ForEach(flow.receivedWindows) { w in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(w.techniqueName)
                                .font(.body.weight(.medium))
                            Text(w.receivedAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            hrvLine(for: w)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section {
                Text("This app is now woken silently by your Apple Watch logging a new HRV sample, usually within 5-15 minutes of finishing a session. You don't need to open the app for it to work.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("HRV data stays on your iPhone and Mac. It is never uploaded.")
                    .font(.caption2)
            }
        }
    }

    @ViewBuilder
    private func hrvLine(for w: PairingFlow.WindowSummary) -> some View {
        if let hrv = w.hrv {
            if let delta = hrv.deltaMs, let pre = hrv.preMs, let post = hrv.postMs {
                let arrow = delta >= 0 ? "↑" : "↓"
                Text("HRV \(arrow) \(String(format: "%.1f ms", abs(delta))) (pre \(String(format: "%.0f", pre)), post \(String(format: "%.0f", post)))")
                    .font(.caption2.monospaced())
                    .foregroundStyle(delta >= 0 ? .green : .orange)
            } else {
                Text("Not enough HRV samples in this window")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Computing HRV…")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var statusColor: Color {
        switch flow.state {
        case .paired, .receivingWindow: return .green
        case .authenticating, .connecting: return .yellow
        case .failed: return .red
        case .idle: return .gray
        }
    }

    private var stateDescription: String {
        switch flow.state {
        case .idle: return "Not connected. Tap a paired Mac on your Mac's Niyora app to reconnect."
        case .connecting(let name): return "Connecting to \(name)…"
        case .authenticating(let name): return "Authenticating with \(name)…"
        case .paired(let name): return "Connected to \(name). Waiting for sessions."
        case .receivingWindow(let name, let w):
            if let w {
                return "Connected to \(name). Last window: \(w.techniqueName)."
            }
            return "Connected to \(name)."
        case .failed(let reason): return reason
        }
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
                    body: "Niyora Companion uses the camera only to scan the pairing QR on your Mac. Enable camera access in Settings → Niyora Companion."
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
