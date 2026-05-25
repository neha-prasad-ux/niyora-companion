import Foundation

/// On-disk store for completed breathing sessions. Persists across app
/// launches in the app's Documents directory. Tracks all completed
/// sessions so we can compute the user's tier and unlock techniques.
enum LocalSessionStore {

    /// One completed session.
    struct Session: Codable, Equatable, Identifiable {
        let id: String
        let techniqueName: String
        let duration: TimeInterval
        let completed: Bool
        let timestamp: Date
        /// Optional mood rating (1-5) captured post-session.
        let mood: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case techniqueName = "technique_name"
            case duration
            case completed
            case timestamp
            case mood
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

    static func all() -> [Session] {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let sessions = try? JSONDecoder().decode([Session].self, from: data)
        else { return [] }
        return sessions
    }

    /// Count of completed sessions only. Used for tier progression.
    static func completedCount() -> Int {
        all().filter(\.completed).count
    }

    /// Add a new session to the store.
    static func add(session: Session) {
        var items = all()
        items.append(session)
        save(items)
    }

    /// Clear all sessions. Used on unpair or reset.
    static func clear() {
        save([])
    }

    private static func save(_ items: [Session]) {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
