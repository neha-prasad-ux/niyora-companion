import XCTest
@testable import NiyoraCompanion

/// Tests `KnownServerStore`'s UserDefaults-backed list. Each test
/// inserts servers with UUID-based IDs and cleans them up in `tearDown`
/// so we never depend on a fully-empty store (other code paths or the
/// app itself may have written entries).
final class KnownServerStoreTests: XCTestCase {
    private var inserted: [String] = []

    override func tearDown() {
        for id in inserted {
            KnownServerStore.remove(serverId: id)
        }
        inserted = []
        super.tearDown()
    }

    private func makeServer(id: String, name: String = "Test Mac", host: String = "192.168.1.10", port: UInt16 = 51820) -> KnownServer {
        KnownServer(serverId: id, serverName: name, host: host, port: port)
    }

    private func track(_ id: String) {
        inserted.append(id)
    }

    func test_upsert_thenAll_containsServer() {
        let id = UUID().uuidString
        track(id)
        let server = makeServer(id: id, name: "Neha's Mac")

        KnownServerStore.upsert(server)

        let all = KnownServerStore.all()
        XCTAssertTrue(all.contains(server), "all() should include the upserted server")
    }

    func test_upsertExistingId_replaces() {
        let id = UUID().uuidString
        track(id)
        let original = makeServer(id: id, name: "Original Name", host: "10.0.0.1", port: 51820)
        let updated  = makeServer(id: id, name: "New Name",     host: "10.0.0.2", port: 51821)

        KnownServerStore.upsert(original)
        KnownServerStore.upsert(updated)

        let matching = KnownServerStore.all().filter { $0.serverId == id }
        XCTAssertEqual(matching.count, 1, "upsert with existing serverId should not duplicate")
        XCTAssertEqual(matching.first, updated)
    }

    func test_remove_removesOnlyTargetedServer() {
        let keepId = UUID().uuidString
        let dropId = UUID().uuidString
        track(keepId)
        track(dropId)

        let keep = makeServer(id: keepId, name: "Keep")
        let drop = makeServer(id: dropId, name: "Drop")

        KnownServerStore.upsert(keep)
        KnownServerStore.upsert(drop)

        KnownServerStore.remove(serverId: dropId)

        let all = KnownServerStore.all()
        XCTAssertTrue(all.contains(keep))
        XCTAssertFalse(all.contains(drop))
        XCTAssertFalse(all.contains(where: { $0.serverId == dropId }))
    }

    func test_remove_onMissingId_isNoop() {
        let id = UUID().uuidString
        track(id)
        let server = makeServer(id: id)
        KnownServerStore.upsert(server)

        // Removing an unrelated, never-inserted ID shouldn't affect ours.
        KnownServerStore.remove(serverId: UUID().uuidString)

        XCTAssertTrue(KnownServerStore.all().contains(server))
    }

    func test_all_returnsAllInsertedServers() {
        let ids = (0..<3).map { _ in UUID().uuidString }
        ids.forEach { track($0) }
        let servers = ids.enumerated().map { i, id in
            makeServer(id: id, name: "Mac \(i)", host: "10.0.0.\(i)", port: UInt16(51820 + i))
        }

        servers.forEach { KnownServerStore.upsert($0) }

        let all = KnownServerStore.all()
        for s in servers {
            XCTAssertTrue(all.contains(s), "all() missing \(s.serverName)")
        }
    }

    func test_upsert_thenRemoveAll_leavesOursAbsent() {
        let id = UUID().uuidString
        track(id)
        let server = makeServer(id: id)

        KnownServerStore.upsert(server)
        KnownServerStore.remove(serverId: id)

        XCTAssertFalse(KnownServerStore.all().contains(where: { $0.serverId == id }))
    }
}
