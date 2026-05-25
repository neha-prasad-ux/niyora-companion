import Foundation

/// On-disk store of completed (or abandoned) breathing sessions.
///
/// Persists as a flat JSON array at `sessions.json` in the app's
/// Documents directory. Sibling issues write sessions here as the
/// user completes guided breathing; the My Soul tab reads them back
/// for display.
///
/// Thread-safe only at the file level (atomic writes). Callers are
/// expected to be on the main actor in practice.
enum LocalSessionStore {

    /// One recorded breathing session.
    struct Session: Codable, Equatable, Identifiable {
        var id: Date { timestamp }
        let technique: String
        let durationSec: Int
        let completed: Bool
        let timestamp: Date
    }

    private static let fileName = "sessions.json"

    private static var fileURL: URL {
        URL.documentsDirectory.appending(path: fileName)
    }

    /// Append a session to the store.
    static func add(session: Session) {
        var items = all()
        items.append(session)
        save(items)
    }

    /// Every recorded session, oldest first.
    static func all() -> [Session] {
        guard let data = try? Data(contentsOf: fileURL),
              let sessions = try? decoder.decode([Session].self, from: data)
        else { return [] }
        return sessions
    }

    /// Total number of recorded sessions.
    static func count() -> Int {
        all().count
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
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
