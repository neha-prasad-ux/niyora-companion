import CryptoKit
import Foundation
import Network
import UIKit

/// State machine that drives a `MacConnection` through the protocol
/// lifecycle (`identify → hello → challenge → auth → authed → window`)
/// and stores the resulting shared secret in the Keychain on success.
///
/// One instance owns the connection lifetime. The owning view layer
/// subscribes to `state` (Observation) to render UI.
@MainActor
@Observable
final class PairingFlow {

    enum State: Equatable {
        case idle
        case connecting(serverName: String)
        case authenticating(serverName: String)
        case paired(serverName: String)
        case receivingWindow(serverName: String, lastWindow: WindowSummary?)
        case failed(reason: String)
    }

    struct WindowSummary: Equatable, Identifiable {
        let id: String      // session_id ‑ idempotent across queue replays
        let techniqueName: String
        let start: String
        let end: String
        let receivedAt: Date
        /// Populated asynchronously once HealthKit has been read for the
        /// pre/post windows. `nil` while still computing; non-nil once the
        /// result has also been sent back to the Mac as `hrv_result`.
        var hrv: WindowHRVDelta?
    }

    var state: State = .idle
    var receivedWindows: [WindowSummary] = []

    private var connection: MacConnection?
    private var runTask: Task<Void, Never>?
    private let healthKit = HealthKitManager()

    private static let wireDateParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

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
        Task { await conn?.cancel() }
        state = .idle
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
                    // First-time pair · prompt for HealthKit access now,
                    // while the user is engaged with the pairing flow and
                    // the "we need HRV" intent is fresh. iOS only shows
                    // the sheet once per type anyway.
                    Task { await self.healthKit.requestAccess() }
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
            case .window:
                state = .failed(reason: "Mac sent a window before authentication.")
                return
            }
        }

        // Main loop: receive windows until the peer closes or task is
        // cancelled. iOS will suspend us shortly after the app backgrounds
        // (the M6 work and HealthKit Background Delivery in PR 3 cover
        // the wake-and-drain path).
        do {
            while let msg = try await stream.next() {
                switch msg {
                case .window(let sessionId, let start, let end, let techniqueName):
                    let summary = WindowSummary(
                        id: sessionId,
                        techniqueName: techniqueName,
                        start: start,
                        end: end,
                        receivedAt: Date(),
                        hrv: nil
                    )
                    if !receivedWindows.contains(where: { $0.id == summary.id }) {
                        receivedWindows.insert(summary, at: 0)
                        if receivedWindows.count > 50 {
                            receivedWindows.removeLast(receivedWindows.count - 50)
                        }
                    }
                    state = .receivingWindow(serverName: serverName, lastWindow: summary)
                    Task { [weak self] in
                        await self?.computeAndSendHrv(
                            sessionId: sessionId,
                            startIso: start,
                            endIso: end
                        )
                    }
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

    /// Read HRV for the pre/post windows around this session and send the
    /// result back to the Mac. Best-effort · failures here never affect the
    /// pairing connection. The Mac side already accepts a `noData` result,
    /// matching the spec's "honest gaps" rule for sparse Watch samples.
    private func computeAndSendHrv(sessionId: String, startIso: String, endIso: String) async {
        guard let start = Self.wireDateParser.date(from: startIso),
              let end = Self.wireDateParser.date(from: endIso) else {
            return
        }
        let delta = await healthKit.computeWindowDelta(sessionStart: start, sessionEnd: end)

        if let idx = receivedWindows.firstIndex(where: { $0.id == sessionId }) {
            var updated = receivedWindows[idx]
            updated.hrv = delta
            receivedWindows[idx] = updated
        }

        let message = ClientMessage.hrvResult(
            sessionId: sessionId,
            preMs: delta.preMs,
            postMs: delta.postMs,
            deltaMs: delta.deltaMs,
            sampleCounts: HrvSampleCounts(pre: delta.preCount, post: delta.postCount),
            status: delta.status
        )
        do {
            try await connection?.send(message)
        } catch {
            // Connection drop is fine · the Mac will request the result again
            // next time the phone reconnects (when M6's queue replay drives
            // the same window through).
        }
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
