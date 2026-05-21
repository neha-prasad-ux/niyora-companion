import CryptoKit
import Foundation
import Network
import UIKit

/// State machine that drives a `MacConnection` through the protocol
/// lifecycle (`identify → hello → challenge → auth → authed →
/// request_measurement`) and stores the resulting shared secret in the
/// Keychain on success.
///
/// One instance owns the connection lifetime. The owning view layer
/// subscribes to `state` (Observation) to render UI, and to
/// `pendingRequest` to know when to present the measurement sheet.
@MainActor
@Observable
final class PairingFlow {

    enum State: Equatable {
        case idle
        case connecting(serverName: String)
        case authenticating(serverName: String)
        case paired(serverName: String)
        case measuring(serverName: String, sessionId: String, phase: MeasurementPhase)
        case failed(reason: String)
    }

    /// One measurement the Mac has asked us to take. The view layer
    /// reads this to decide whether to present the sheet, and clears it
    /// once the result has been sent back (or the sheet is dismissed).
    struct PendingRequest: Equatable, Identifiable {
        var id: String { "\(sessionId):\(phase.rawValue)" }
        let sessionId: String
        let phase: MeasurementPhase
        let techniqueName: String
    }

    var state: State = .idle
    /// The most recently received `request_measurement` from the Mac
    /// that has not yet been resolved. ContentView watches this and
    /// presents `MeasurementSheet` when non-nil.
    var pendingRequest: PendingRequest?
    /// session_id:phase keys already handled this connection, so a
    /// queue replay does not re-prompt the user for a capture they
    /// already produced. Reset on disconnect.
    private var seenRequests: Set<String> = []

    private var connection: MacConnection?
    private var runTask: Task<Void, Never>?

    /// Pair for the first time with a freshly scanned QR.
    func pair(with payload: QrPayload) {
        startConnection(
            host: payload.host,
            port: payload.port,
            serverId: payload.serverId,
            serverName: payload.serverName,
            secret: Hex.decode(payload.secretHex),
            pairingId: payload.pairingId
        )
    }

    /// Reconnect to a Mac we've paired with before.
    func reconnect(to known: KnownServer) {
        startConnection(
            host: known.host,
            port: known.port,
            serverId: known.serverId,
            serverName: known.serverName,
            secret: KeychainStore.loadSecret(forServerId: known.serverId),
            pairingId: nil
        )
    }

    func disconnect() {
        runTask?.cancel()
        runTask = nil
        let conn = connection
        connection = nil
        seenRequests.removeAll()
        pendingRequest = nil
        Task { await conn?.cancel() }
        state = .idle
    }

    /// Called by the measurement sheet once the controller produces a
    /// final result. Sends the `hrv_result` frame back to the Mac and
    /// clears the pending request so the next one can surface.
    func sendResult(
        sessionId: String,
        phase: MeasurementPhase,
        result: PPGMeasurementResult
    ) async {
        let message = ClientMessage.hrvResult(
            sessionId: sessionId,
            phase: phase,
            rmssdMs: result.rmssdMs,
            sdnnMs: result.sdnnMs,
            sampleCount: result.sampleCount,
            snrDb: result.snrDb,
            status: result.status
        )
        do {
            try await connection?.send(message)
        } catch {
            // Connection drop is fine · the Mac will request the same
            // measurement again next time the phone reconnects (queue
            // replay), and the seenRequests cache resets on disconnect.
        }
        pendingRequest = nil
        if case let .measuring(name, _, _) = state {
            state = .paired(serverName: name)
        }
    }

    /// Dismiss the current request without producing a result · used
    /// when the user closes the sheet before the capture completes and
    /// the controller emits a `.cancelled` result.
    func clearPendingRequest() {
        pendingRequest = nil
        if case let .measuring(name, _, _) = state {
            state = .paired(serverName: name)
        }
    }

    // MARK: - Private

    private func startConnection(
        host: String,
        port: UInt16,
        serverId: String,
        serverName: String,
        secret: Data?,
        pairingId: String?
    ) {
        runTask?.cancel()
        let priorConnection = connection
        connection = nil
        Task { await priorConnection?.cancel() }
        seenRequests.removeAll()
        pendingRequest = nil

        guard let secret else {
            state = .failed(reason: pairingId == nil
                ? "No saved pairing for \(serverName). Scan the QR again."
                : "QR contained an invalid secret.")
            return
        }

        state = .connecting(serverName: serverName)

        runTask = Task { [weak self] in
            await self?.run(
                host: host,
                port: port,
                serverId: serverId,
                serverName: serverName,
                secret: secret,
                pairingId: pairingId
            )
        }
    }

    private func run(
        host: String,
        port: UInt16,
        serverId: String,
        serverName: String,
        secret: Data,
        pairingId: String?
    ) async {
        let conn = MacConnection(host: host, port: port)
        self.connection = conn

        do {
            try await conn.start()
        } catch {
            state = .failed(reason: friendlyConnectError(error))
            return
        }

        let clientId = KeychainStore.clientId()
        let clientName = UIDevice.current.name.isEmpty ? "iPhone" : UIDevice.current.name

        do {
            try await conn.send(.identify(
                clientId: clientId,
                clientName: clientName,
                pairingId: pairingId
            ))
        } catch {
            state = .failed(reason: "Could not greet the Mac.")
            return
        }

        state = .authenticating(serverName: serverName)

        var stream = await conn.messages().makeAsyncIterator()
        var receivedHello = false
        var receivedAuthed = false

        while !receivedAuthed {
            let msg: ServerMessage?
            do {
                msg = try await stream.next()
            } catch {
                state = .failed(reason: "Connection dropped before pairing finished.")
                return
            }
            guard let msg else {
                state = .failed(reason: "Mac closed the connection before pairing finished.")
                return
            }
            switch msg {
            case .hello:
                receivedHello = true
            case .challenge(let nonceHex):
                guard receivedHello else {
                    state = .failed(reason: "Mac sent challenge before hello.")
                    return
                }
                guard let nonce = Hex.decode(nonceHex) else {
                    state = .failed(reason: "Mac sent a malformed challenge.")
                    return
                }
                let tag = HMAC<SHA256>.authenticationCode(
                    for: nonce,
                    using: SymmetricKey(data: secret)
                )
                do {
                    try await conn.send(.auth(hmacHex: Hex.encode(Data(tag))))
                } catch {
                    state = .failed(reason: "Could not send proof to the Mac.")
                    return
                }
            case .authed:
                receivedAuthed = true
                if pairingId != nil {
                    _ = KeychainStore.storeSecret(secret, forServerId: serverId)
                }
                KnownServerStore.upsert(KnownServer(
                    serverId: serverId,
                    serverName: serverName,
                    host: host,
                    port: port
                ))
                state = .paired(serverName: serverName)
            case .authFailed(let reason):
                state = .failed(reason: "Mac refused the pairing: \(reason)")
                return
            case .requestMeasurement:
                state = .failed(reason: "Mac sent a measurement request before authentication.")
                return
            }
        }

        // Main loop: receive measurement requests until the peer closes
        // or the task is cancelled. iOS will suspend us shortly after
        // the app backgrounds · the PPG path is foreground-only by
        // design (the user has to hold their finger on the lens), so a
        // dropped connection is not a regression here.
        do {
            while let msg = try await stream.next() {
                switch msg {
                case .requestMeasurement(let sessionId, let phase, let techniqueName):
                    let key = "\(sessionId):\(phase.rawValue)"
                    if seenRequests.contains(key) { continue }
                    seenRequests.insert(key)
                    pendingRequest = PendingRequest(
                        sessionId: sessionId,
                        phase: phase,
                        techniqueName: techniqueName
                    )
                    state = .measuring(serverName: serverName, sessionId: sessionId, phase: phase)
                default:
                    state = .failed(reason: "Mac sent an unexpected message after authentication.")
                    return
                }
            }
        } catch {
            state = .failed(reason: "Connection dropped.")
            return
        }

        // Peer closed cleanly. UI can render an offer to reconnect.
        state = .idle
    }

    private func friendlyConnectError(_ error: Error) -> String {
        guard let connErr = error as? MacConnection.ConnectionError else {
            return error.localizedDescription
        }
        switch connErr {
        case .waiting:
            return "Waiting for the Mac to respond. Make sure you're on the same wifi as your Mac, and that Niyora is open. If iOS asked for Local Network access, allow it under Settings → Niyora Companion."
        case .transport:
            return "Could not reach the Mac. Make sure Niyora is open and on the same wifi."
        case .decoding(let why):
            return "The Mac sent something unexpected: \(why)"
        case .cancelled:
            return "Cancelled."
        }
    }
}

