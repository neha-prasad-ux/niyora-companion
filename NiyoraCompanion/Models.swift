import Foundation

/// One HRV (SDNN) sample, in milliseconds, as recorded by the Apple Watch.
struct HRVReading: Identifiable {
    let id = UUID()
    let date: Date
    let sdnnMs: Double
}

/// The result of computing pre/post HRV for a session window. Either both
/// sides have data (delta is real) or at least one is empty (status is
/// `noData` and the Mac shows "not enough data this time", per the spec's
/// honest-gaps rule).
struct WindowHRVDelta: Equatable {
    let preMs: Double?
    let postMs: Double?
    let preCount: UInt32
    let postCount: UInt32

    /// Whether both sides have at least one sample.
    var hasBothSides: Bool {
        preMs != nil && postMs != nil
    }

    /// post - pre when both sides exist.
    var deltaMs: Double? {
        guard let pre = preMs, let post = postMs else { return nil }
        return post - pre
    }

    var status: HrvResultStatus {
        hasBothSides ? .ok : .noData
    }
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
