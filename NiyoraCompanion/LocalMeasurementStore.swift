import Foundation

/// On-disk queue of measurement results that have not yet been
/// delivered to the Mac. Symmetric with the Mac-side
/// `companion_queue.json` for outgoing RequestMeasurement frames.
///
/// The queue is small (cap 50) and persists across app launches in the
/// app's Documents directory. Used when the phone takes a measurement
/// while not connected to the Mac · the result is appended here, then
/// drained the next time PairingFlow reaches a paired state.
enum LocalMeasurementStore {

    /// One queued result. Mirrors the wire frame fields so we can
    /// reconstruct a `ClientMessage.hrvResult` on drain.
    struct Pending: Codable, Equatable, Identifiable {
        var id: String { "\(sessionId):\(phase)" }
        let sessionId: String
        let phase: String
        let rmssdMs: Double?
        let sdnnMs: Double?
        let sampleCount: UInt32
        let snrDb: Double?
        let status: String
        let queuedAtIso: String

        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case phase
            case rmssdMs = "rmssd_ms"
            case sdnnMs = "sdnn_ms"
            case sampleCount = "sample_count"
            case snrDb = "snr_db"
            case status
            case queuedAtIso = "queued_at"
        }
    }

    private static let capacity = 50
    private static let fileName = "local_measurement_queue.json"

    private static var fileURL: URL? {
        let fm = FileManager.default
        guard let docs = try? fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return docs.appendingPathComponent(fileName)
    }

    static func load() -> [Pending] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let pending = try? JSONDecoder().decode([Pending].self, from: data)
        else { return [] }
        return pending
    }

    /// Append a result to the queue. Idempotent on (session_id, phase)
    /// · re-queueing the same row replaces the older entry. Drops the
    /// oldest entry first if at cap.
    static func enqueue(_ pending: Pending) {
        var items = load()
        items.removeAll { $0.id == pending.id }
        items.append(pending)
        while items.count > capacity {
            items.removeFirst()
        }
        save(items)
    }

    /// Remove a single queued entry, e.g. after a successful send.
    static func remove(sessionId: String, phase: String) {
        var items = load()
        let id = "\(sessionId):\(phase)"
        items.removeAll { $0.id == id }
        save(items)
    }

    /// Clear the entire queue. Used on unpair · stale results from a
    /// no-longer-paired Mac aren't useful.
    static func clear() {
        save([])
    }

    private static func save(_ items: [Pending]) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(items)
        else { return }
        try? data.write(to: url, options: .atomic)
    }
}
