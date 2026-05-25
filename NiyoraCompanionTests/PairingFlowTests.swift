import XCTest
@testable import NiyoraCompanion

/// Tests for `PairingFlow`'s state machine.
///
/// LIMITATIONS:
///
/// `PairingFlow` constructs a real `MacConnection` (Network.framework
/// `NWConnection`) when `pair()` or `reconnect()` succeeds past the hex
/// decode. There is no injection seam for a mock connection, so we can
/// only deterministically exercise:
///
///   - initial state `.idle`
///   - `pair()` immediate-fail path (invalid hex secret)
///   - `reconnect()` immediate-fail path (no saved secret in the Keychain
///     for an unknown server id)
///   - `startStandaloneMeasurement()` sets `pendingRequest`
///   - `clearPendingRequest()` clears it and resets `.measuring` → `.paired`
///   - `disconnect()` returns to `.idle` and clears `pendingRequest`
///
/// TODO: To test the connecting → authenticating → paired sequence and the
/// hello/challenge/auth handshake, production code would need a
/// `MacConnectionProtocol` injectable surface. That is out of scope here
/// per the task constraints (do not modify production source).
@MainActor
final class PairingFlowTests: XCTestCase {

    // MARK: - Helpers

    private func makeQrPayload(secretHex: String) -> QrPayload {
        QrPayload(
            v: 2,
            serverId: "server-test-\(UUID().uuidString)",
            serverName: "Test Mac",
            host: "127.0.0.1",
            port: 9999,
            pairingId: "pairing-\(UUID().uuidString)",
            secretHex: secretHex
        )
    }

    private func makeKnownServer() -> KnownServer {
        // serverId is unique per call so no leftover Keychain entry from
        // a prior test run can satisfy the secret lookup.
        KnownServer(
            serverId: "unknown-server-\(UUID().uuidString)",
            serverName: "Unknown Mac",
            host: "127.0.0.1",
            port: 9999
        )
    }

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let flow = PairingFlow()
        XCTAssertEqual(flow.state, .idle)
        XCTAssertNil(flow.pendingRequest)
    }

    // MARK: - pair() with invalid secret

    func test_pair_withInvalidHexSecret_transitionsToFailed() {
        let flow = PairingFlow()
        // Odd-length hex · Hex.decode returns nil.
        let payload = makeQrPayload(secretHex: "abc")
        flow.pair(with: payload)
        guard case let .failed(reason) = flow.state else {
            XCTFail("expected .failed, got \(flow.state)")
            return
        }
        XCTAssertTrue(reason.contains("invalid"), "reason should mention invalid secret, got: \(reason)")
    }

    func test_pair_withNonHexCharacters_transitionsToFailed() {
        let flow = PairingFlow()
        // Even length but contains non-hex chars · Hex.decode returns nil.
        let payload = makeQrPayload(secretHex: "zzzz")
        flow.pair(with: payload)
        guard case .failed = flow.state else {
            XCTFail("expected .failed, got \(flow.state)")
            return
        }
    }

    // MARK: - reconnect() with no saved secret

    func test_reconnect_withNoSavedSecret_transitionsToFailed() {
        let flow = PairingFlow()
        let known = makeKnownServer()
        // Sanity: scrub anything that might be left over for this id.
        KeychainStore.deleteSecret(forServerId: known.serverId)
        flow.reconnect(to: known)
        guard case let .failed(reason) = flow.state else {
            XCTFail("expected .failed, got \(flow.state)")
            return
        }
        XCTAssertTrue(reason.contains("No saved pairing"),
                      "reason should mention no saved pairing, got: \(reason)")
    }

    // MARK: - disconnect()

    func test_disconnect_fromIdle_remainsIdle() {
        let flow = PairingFlow()
        flow.disconnect()
        XCTAssertEqual(flow.state, .idle)
        XCTAssertNil(flow.pendingRequest)
    }

    func test_disconnect_clearsPendingRequest() {
        let flow = PairingFlow()
        flow.startStandaloneMeasurement()
        XCTAssertNotNil(flow.pendingRequest)
        flow.disconnect()
        XCTAssertNil(flow.pendingRequest)
        XCTAssertEqual(flow.state, .idle)
    }

    func test_disconnect_fromFailedReturnsToIdle() {
        let flow = PairingFlow()
        let payload = makeQrPayload(secretHex: "zz") // forces .failed
        flow.pair(with: payload)
        if case .failed = flow.state { /* ok */ } else {
            XCTFail("setup did not reach .failed, got \(flow.state)")
            return
        }
        flow.disconnect()
        XCTAssertEqual(flow.state, .idle)
    }

    // MARK: - startStandaloneMeasurement

    func test_startStandaloneMeasurement_setsPendingRequestPostPhase() {
        let flow = PairingFlow()
        flow.startStandaloneMeasurement()
        guard let req = flow.pendingRequest else {
            XCTFail("expected pendingRequest to be set")
            return
        }
        XCTAssertEqual(req.phase, .post)
        XCTAssertTrue(req.isStandalone)
        XCTAssertEqual(req.techniqueName, "")
        XCTAssertFalse(req.sessionId.isEmpty)
    }

    func test_startStandaloneMeasurement_mintsFreshSessionIdEachCall() {
        let flow = PairingFlow()
        flow.startStandaloneMeasurement()
        let firstId = flow.pendingRequest?.sessionId
        flow.startStandaloneMeasurement()
        let secondId = flow.pendingRequest?.sessionId
        XCTAssertNotNil(firstId)
        XCTAssertNotNil(secondId)
        XCTAssertNotEqual(firstId, secondId)
    }

    // MARK: - clearPendingRequest

    func test_clearPendingRequest_nilsTheRequest() {
        let flow = PairingFlow()
        flow.startStandaloneMeasurement()
        XCTAssertNotNil(flow.pendingRequest)
        flow.clearPendingRequest()
        XCTAssertNil(flow.pendingRequest)
    }

    func test_clearPendingRequest_doesNotChangeIdleState() {
        let flow = PairingFlow()
        flow.startStandaloneMeasurement()
        flow.clearPendingRequest()
        // Was .idle, should still be .idle (no .measuring to drop back from).
        XCTAssertEqual(flow.state, .idle)
    }

    // MARK: - PendingRequest identity

    func test_pendingRequest_idCombinesSessionAndPhase() {
        let r = PairingFlow.PendingRequest(
            sessionId: "abc",
            phase: .pre,
            techniqueName: "Box",
            isStandalone: false
        )
        XCTAssertEqual(r.id, "abc:pre")
    }

    func test_pendingRequest_equatable() {
        let a = PairingFlow.PendingRequest(
            sessionId: "s", phase: .pre, techniqueName: "Box", isStandalone: false
        )
        let b = PairingFlow.PendingRequest(
            sessionId: "s", phase: .pre, techniqueName: "Box", isStandalone: false
        )
        let c = PairingFlow.PendingRequest(
            sessionId: "s", phase: .post, techniqueName: "Box", isStandalone: false
        )
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - State equality (Equatable conformance)

    func test_stateEquality_distinguishesVariants() {
        XCTAssertEqual(PairingFlow.State.idle, .idle)
        XCTAssertEqual(
            PairingFlow.State.connecting(serverName: "A"),
            PairingFlow.State.connecting(serverName: "A")
        )
        XCTAssertNotEqual(
            PairingFlow.State.connecting(serverName: "A"),
            PairingFlow.State.connecting(serverName: "B")
        )
        XCTAssertNotEqual(
            PairingFlow.State.connecting(serverName: "A"),
            PairingFlow.State.authenticating(serverName: "A")
        )
        XCTAssertEqual(
            PairingFlow.State.paired(serverName: "Mac"),
            PairingFlow.State.paired(serverName: "Mac")
        )
        XCTAssertEqual(
            PairingFlow.State.measuring(serverName: "M", sessionId: "s", phase: .pre),
            PairingFlow.State.measuring(serverName: "M", sessionId: "s", phase: .pre)
        )
        XCTAssertNotEqual(
            PairingFlow.State.measuring(serverName: "M", sessionId: "s", phase: .pre),
            PairingFlow.State.measuring(serverName: "M", sessionId: "s", phase: .post)
        )
        XCTAssertEqual(
            PairingFlow.State.failed(reason: "x"),
            PairingFlow.State.failed(reason: "x")
        )
        XCTAssertNotEqual(
            PairingFlow.State.failed(reason: "x"),
            PairingFlow.State.failed(reason: "y")
        )
    }
}
