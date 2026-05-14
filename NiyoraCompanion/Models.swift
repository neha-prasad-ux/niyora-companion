import Foundation

/// One HRV (SDNN) sample, in milliseconds, as recorded by the Apple Watch.
struct HRVReading: Identifiable {
    let id = UUID()
    let date: Date
    let sdnnMs: Double
}

/// The result of reading HRV over a time window. An empty `samples` array is
/// a normal, expected outcome: HRV is sparse and a short window may contain
/// nothing. `error` is set only when the HealthKit query itself failed.
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
