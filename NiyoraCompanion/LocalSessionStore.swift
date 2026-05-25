import Foundation

/// On-disk store for completed (or abandoned) breathing sessions.
///
/// Persists across app launches as a JSON array in the app's Documents
/// directory. Used by the Breath flow to record each session and by the
/// My Soul tab to compute tier progression and render recent history.
///
/// One row per session. A session that has both pre and post captures
/// still counts as a single session.
///
/// Thread-safe only at the file level (atomic writes). Callers are
/// expected to be on the main actor in practice.
enum LocalSessionStore {

    /// One recorded session.
    struct Session: Codable, Equatable, Identifiable {
        let id: String
        let techniqueName: String
        let duration: TimeInterval
        let completed: Bool
        let timestamp: Date
        /// Optional mood rating (1-5) captured post-session.
        let mood: Int?
        /// True when the session was started standalone on the phone (not
        /// triggered by a paired Mac via "Measure stress"). Defaults to
        /// true on decode for older rows that predate this field, so v1
        /// data written before this property existed is treated as
        /// standalone.
        let isStandalone: Bool

        /// ISO 8601 string form of `timestamp`. The My Soul tab renders
        /// relative time from this value; keeping it as a computed
        /// property avoids a second source of truth in the on-disk row.
        var completedAtIso: String {
            ISO8601DateFormatter().string(from: timestamp)
        }

        enum CodingKeys: String, CodingKey {
            case id
            case techniqueName = "technique_name"
            case duration
            case completed
            case timestamp
            case mood
            case isStandalone = "is_standalone"
        }

        init(
            id: String,
            techniqueName: String,
            duration: TimeInterval,
            completed: Bool,
            timestamp: Date,
            mood: Int? = nil,
            isStandalone: Bool = true
        ) {
            self.id = id
            self.techniqueName = techniqueName
            self.duration = duration
            self.completed = completed
            self.timestamp = timestamp
            self.mood = mood
            self.isStandalone = isStandalone
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try c.decode(String.self, forKey: .id)
            self.techniqueName = try c.decode(String.self, forKey: .techniqueName)
            self.duration = try c.decode(TimeInterval.self, forKey: .duration)
            self.completed = try c.decode(Bool.self, forKey: .completed)
            self.timestamp = try c.decode(Date.self, forKey: .timestamp)
            self.mood = try c.decodeIfPresent(Int.self, forKey: .mood)
            // Default to standalone for older rows that predate the field.
            self.isStandalone = try c.decodeIfPresent(Bool.self, forKey: .isStandalone) ?? true
        }
    }

    private static let fileName = "breath_sessions.json"

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

    /// All sessions, most recent first.
    static func all() -> [Session] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let sessions = try? decoder.decode([Session].self, from: data)
        else { return [] }
        return sessions.sorted { $0.timestamp > $1.timestamp }
    }

    /// Total count of recorded sessions (completed and abandoned).
    static func count() -> Int {
        all().count
    }

    /// Count of completed sessions only. Used for tier progression.
    static func completedCount() -> Int {
        all().filter(\.completed).count
    }

    /// Append a new session to the store. Idempotent on `id` (a re-add
    /// with the same id replaces the older entry, though in practice
    /// each session is minted with a fresh UUID).
    static func add(session: Session) {
        var items = all()
        items.removeAll { $0.id == session.id }
        items.append(session)
        save(items)
    }

    /// Clear all sessions. Used on unpair or reset.
    static func clear() {
        save([])
    }

    // MARK: - Private

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static func save(_ items: [Session]) {
        guard let url = fileURL,
              let data = try? encoder.encode(items)
        else { return }
        try? data.write(to: url, options: .atomic)
    }
}
