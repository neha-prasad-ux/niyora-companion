import Foundation

/// Friendly identity of a Mac the user has paired with. Endpoint
/// (host/port) is the last-seen value from a fresh QR pairing and is
/// likely stale across DHCP rotations; M4 doesn't try to re-discover via
/// mDNS (M6's job). Re-pair brings it current.
struct KnownServer: Codable, Identifiable, Equatable {
    var id: String { serverId }
    let serverId: String
    let serverName: String
    let host: String
    let port: UInt16
}

/// UserDefaults-backed list of Macs the user has paired with. Secrets
/// live in the Keychain ‑ this file holds only non-sensitive metadata.
/// UserDefaults is fine for ≤handful entries with simple Codable types.
enum KnownServerStore {
    private static let key = "niyora.companion.known_servers.v1"

    static func all() -> [KnownServer] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let arr = try? JSONDecoder().decode([KnownServer].self, from: data)
        else { return [] }
        return arr
    }

    static func upsert(_ server: KnownServer) {
        var list = all().filter { $0.serverId != server.serverId }
        list.append(server)
        save(list)
    }

    static func remove(serverId: String) {
        save(all().filter { $0.serverId != serverId })
    }

    private static func save(_ list: [KnownServer]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
