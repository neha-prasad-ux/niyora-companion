import Foundation

/// Which side of a breathing session a capture covers. Matches the wire
/// frame's `phase` string · `Codable` round-trips through the raw value.
enum MeasurementPhase: String, Codable, Equatable {
    case pre
    case post
}

/// One HRV (SDNN) sample, in milliseconds, as recorded by the Apple
/// Watch. Used only by the DEBUG HealthKit spike screen now · the
/// shipping path is PPG, not HealthKit.
struct HRVReading: Identifiable {
    let id = UUID()
    let date: Date
    let sdnnMs: Double
}

/// The result of computing HRV from a 30s PPG capture. Either status is
/// `.ok` and both metrics are present, or status explains why metrics
/// are absent (see `HrvResultStatus`).
struct PPGMeasurementResult: Equatable {
    /// Root-mean-square of successive IBI differences. The primary HRV
    /// metric for short PPG · nil unless status is `.ok`.
    let rmssdMs: Double?
    /// Standard deviation of IBIs. Secondary · also nil unless `.ok`.
    let sdnnMs: Double?
    /// Number of inter-beat intervals detected in the capture.
    let sampleCount: UInt32
    /// Estimated signal-to-noise ratio in dB. Forwarded to the Mac.
    let snrDb: Double?
    let status: HrvResultStatus
}

/// The result of reading HRV over a time window. An empty `samples`
/// array is normal · HRV is sparse and a short window may contain
/// nothing. Used only by the DEBUG spike screen.
struct HRVWindow {
    let start: Date
    let end: Date
    let samples: [HRVReading]
    let error: String?

    /// Mean SDNN across the window, or nil if there were no samples.
    var meanSdnnMs: Double? {
        guard !samples.isEmpty else { return nil }
        return samples.map(\.sdnnMs).reduce(0, +) / Double(samples.count)
    }
}
