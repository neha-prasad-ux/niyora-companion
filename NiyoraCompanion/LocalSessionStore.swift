import Foundation

/// Persistent record of completed breathing sessions. Used by the My Soul
/// tab to show recent history and compute tier progression (session count
/// → Spark / Glow / Radiance / etc.).
///
/// Each session is created when the user completes a standalone measurement
/// (tapping "Measure stress" on the phone) or when a Mac-initiated
/// measurement completes. One row per session; a session that has both pre
/// and post captures still counts as a single session.
enum LocalSessionStore {

    struct Session: Codable, Equatable, Identifiable {
        var id: String { sessionId }
        let sessionId: String
        let completedAtIso: String
        let techniqueName: String
        let isStandalone: Bool

        enum CodingKeys: String, CodingKey {
            case sessionId = "session_id"
            case completedAtIso = "completed_at"
            case techniqueName = "technique_name"
            case isStandalone = "is_standalone"
        }
    }

    private static let fileName = "local_sessions.json"

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

    /// Load all sessions sorted by completion time (most recent first).
    static func all() -> [Session] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let sessions = try? JSONDecoder().decode([Session].self, from: data)
        else { return [] }
        return sessions.sorted { $0.completedAtIso > $1.completedAtIso }
    }

    /// Total count of sessions. Used by tier progression logic.
    static func count() -> Int {
        all().count
    }

    /// Add a new session. Idempotent on sessionId (re-adding the same
    /// session_id replaces the older entry, though in practice this should
    /// not happen since each session gets a fresh UUID).
    static func add(_ session: Session) {
        var items = all()
        items.removeAll { $0.sessionId == session.sessionId }
        items.append(session)
        save(items)
    }

    /// Clear all sessions. Used on unpair.
    static func clear() {
        save([])
    }

    private static func save(_ items: [Session]) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(items)
        else { return }
        try? data.write(to: url, options: .atomic)
    }
}
