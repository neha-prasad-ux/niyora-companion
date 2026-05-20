#if DEBUG
import SwiftUI

/// The original M1-2 HealthKit spike screen. Kept only in DEBUG builds
/// so we can sanity-check that the Watch is writing HRV samples before
/// we ship the M5 background-delivery path. Not part of the user-facing
/// app surface.
struct HRVSpikeView: View {
    @State private var manager = HealthKitManager()
    @State private var windowStart = Date().addingTimeInterval(-24 * 3600)
    @State private var windowEnd = Date()
    @State private var result: HRVWindow?
    @State private var isReading = false

    var body: some View {
        Form {
            availabilitySection
            accessSection
            windowSection
            if let result {
                resultSection(result)
            }
        }
        .navigationTitle("HRV Spike (DEBUG)")
    }

    private var availabilitySection: some View {
        Section("Device") {
            switch manager.availability {
            case .unknown:
                Label("Checking…", systemImage: "hourglass")
            case .unavailable:
                Label("HealthKit not available on this device", systemImage: "xmark.circle")
                    .foregroundStyle(.red)
            case .available:
                Label("HealthKit available", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
        }
    }

    private var accessSection: some View {
        Section {
            Button {
                Task { await manager.requestAccess() }
            } label: {
                Label("Allow HRV access", systemImage: "heart.text.square")
            }
            .disabled(manager.availability != .available)

            switch manager.accessState {
            case .notRequested:
                Text("Not asked yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .requested:
                Text("Permission sheet shown. HealthKit does not report whether read access was granted; run a query below to find out.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .failed:
                Text(manager.lastError ?? "Authorization failed.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("HealthKit access")
        }
    }

    private var windowSection: some View {
        Section("Read window") {
            DatePicker("Start", selection: $windowStart)
            DatePicker("End", selection: $windowEnd)

            HStack {
                quickButton("Last 1h", hours: 1)
                quickButton("Last 24h", hours: 24)
                quickButton("Last 7d", hours: 24 * 7)
            }

            Button {
                Task { await runRead() }
            } label: {
                if isReading {
                    ProgressView()
                } else {
                    Label("Read HRV", systemImage: "waveform.path.ecg")
                }
            }
            .disabled(isReading || manager.availability != .available)
        }
    }

    private func resultSection(_ window: HRVWindow) -> some View {
        Section("Result") {
            if let error = window.error {
                Text(error).foregroundStyle(.red)
            } else if window.samples.isEmpty {
                Text("No HRV samples in this window. That is normal ‑ the Watch logs HRV sparsely. Try a wider window or wear the Watch longer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Samples", value: "\(window.samples.count)")
                if let mean = window.meanSdnnMs {
                    LabeledContent("Mean SDNN", value: String(format: "%.1f ms", mean))
                }
                ForEach(window.samples) { reading in
                    LabeledContent(
                        reading.date.formatted(date: .abbreviated, time: .shortened),
                        value: String(format: "%.1f ms", reading.sdnnMs)
                    )
                    .font(.footnote)
                }
            }
        }
    }

    private func quickButton(_ title: String, hours: Double) -> some View {
        Button(title) {
            windowEnd = Date()
            windowStart = Date().addingTimeInterval(-hours * 3600)
        }
        .buttonStyle(.bordered)
        .font(.footnote)
    }

    private func runRead() async {
        isReading = true
        result = await manager.readHRV(from: windowStart, to: windowEnd)
        isReading = false
    }
}
#endif
