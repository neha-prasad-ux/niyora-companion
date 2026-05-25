import XCTest
@testable import NiyoraCompanion

/// Round-trip tests for `KeychainStore`'s per-Mac shared-secret API.
///
/// These tests touch the real iOS Keychain in the simulator. Every test
/// uses a UUID-based server ID so concurrent or repeated runs don't
/// stomp each other, and `tearDown` deletes whatever was written so the
/// simulator's keychain doesn't accrete junk across runs.
final class KeychainStoreTests: XCTestCase {
    private var serverId: String = ""

    override func setUp() {
        super.setUp()
        serverId = UUID().uuidString
        // Defensive: ensure no leftover from a prior crashed run.
        KeychainStore.deleteSecret(forServerId: serverId)
    }

    override func tearDown() {
        KeychainStore.deleteSecret(forServerId: serverId)
        super.tearDown()
    }

    func test_writeThenRead_returnsSameValue() {
        let secret = Data([0x01, 0x02, 0x03, 0xFF, 0xAA])

        let ok = KeychainStore.storeSecret(secret, forServerId: serverId)
        XCTAssertTrue(ok, "storeSecret should succeed on a fresh keychain entry")

        let readBack = KeychainStore.loadSecret(forServerId: serverId)
        XCTAssertEqual(readBack, secret)
    }

    func test_overwrite_returnsNewValue() {
        let first = Data([0x11, 0x22, 0x33])
        let second = Data([0xAA, 0xBB, 0xCC, 0xDD])

        XCTAssertTrue(KeychainStore.storeSecret(first, forServerId: serverId))
        XCTAssertEqual(KeychainStore.loadSecret(forServerId: serverId), first)

        XCTAssertTrue(KeychainStore.storeSecret(second, forServerId: serverId))
        let readBack = KeychainStore.loadSecret(forServerId: serverId)
        XCTAssertEqual(readBack, second, "overwrite should replace, not append")
        XCTAssertNotEqual(readBack, first)
    }

    func test_delete_removesValue() {
        let secret = Data([0x42, 0x43, 0x44])
        XCTAssertTrue(KeychainStore.storeSecret(secret, forServerId: serverId))
        XCTAssertNotNil(KeychainStore.loadSecret(forServerId: serverId))

        KeychainStore.deleteSecret(forServerId: serverId)

        XCTAssertNil(KeychainStore.loadSecret(forServerId: serverId))
    }

    func test_getOnMissing_returnsNil() {
        // serverId is fresh from setUp; nothing has been written under it.
        XCTAssertNil(KeychainStore.loadSecret(forServerId: serverId))
    }

    func test_distinctServerIds_storeDistinctSecrets() {
        let otherId = UUID().uuidString
        defer { KeychainStore.deleteSecret(forServerId: otherId) }

        let a = Data([0x01, 0x02])
        let b = Data([0x10, 0x20, 0x30])

        XCTAssertTrue(KeychainStore.storeSecret(a, forServerId: serverId))
        XCTAssertTrue(KeychainStore.storeSecret(b, forServerId: otherId))

        XCTAssertEqual(KeychainStore.loadSecret(forServerId: serverId), a)
        XCTAssertEqual(KeychainStore.loadSecret(forServerId: otherId), b)
    }

    func test_clientId_isStableAcrossCalls() {
        // clientId mints once and persists. We can't isolate this from
        // the simulator's keychain, but we can assert the contract: two
        // calls return the same UUID-shaped string.
        let first = KeychainStore.clientId()
        let second = KeychainStore.clientId()
        XCTAssertEqual(first, second)
        XCTAssertNotNil(UUID(uuidString: first), "clientId should be a UUID string")
    }
}
