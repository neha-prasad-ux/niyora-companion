import Foundation
import Network

/// Async NWConnection wrapper that frames the byte stream as NDJSON.
/// One `send(_:)` per outgoing message, one `messages` stream element per
/// incoming line. Lifetime ends when the peer closes or `cancel()` is
/// called from the owning state machine.
///
/// Why NWConnection and not URLSession + WebSocket: the Mac side is a
/// plain TCP socket with no HTTP. NWConnection lives in `Network.framework`,
/// Apple's recommended API for local-network peer-to-peer.
actor MacConnection {

    enum ConnectionError: Error {
        case cancelled
        case decoding(String)
        case transport(NWError)
        case waiting(NWError)
    }

    private let connection: NWConnection
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var messageStreamContinuation: AsyncThrowingStream<ServerMessage, Error>.Continuation?
    private var readBuffer = Data()
    private var hasStartedReading = false

    init(host: String, port: UInt16) {
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let params = NWParameters.tcp
        // Disable Bonjour / multipath optimisations: this is a one-shot
        // direct connect to a known endpoint, not a service browse.
        params.includePeerToPeer = true
        self.connection = NWConnection(host: nwHost, port: nwPort, using: params)
    }

    /// Bring the connection up. Returns once ready, or throws on failure.
    func start() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            startContinuation = cont
            connection.stateUpdateHandler = { [weak self] state in
                Task { await self?.handleState(state) }
            }
            connection.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Async sequence of decoded server messages. Call once; the stream
    /// ends when the peer closes or `cancel()` runs.
    func messages() -> AsyncThrowingStream<ServerMessage, Error> {
        AsyncThrowingStream { continuation in
            Task { await self.attachContinuation(continuation) }
        }
    }

    func send(_ message: ClientMessage) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        var data = try encoder.encode(message)
        data.append(0x0A) // newline ‑ NDJSON framing
        try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<Void, Error>) in
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error {
                        cont.resume(throwing: ConnectionError.transport(error))
                    } else {
                        cont.resume()
                    }
                }
            )
        }
    }

    func cancel() {
        connection.cancel()
        messageStreamContinuation?.finish(throwing: ConnectionError.cancelled)
        messageStreamContinuation = nil
    }

    // MARK: - Private

    private func attachContinuation(_ cont: AsyncThrowingStream<ServerMessage, Error>.Continuation) {
        messageStreamContinuation = cont
        if !hasStartedReading {
            hasStartedReading = true
            scheduleRead()
        }
    }

    private func handleState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            startContinuation?.resume()
            startContinuation = nil
        case .failed(let error):
            let err = ConnectionError.transport(error)
            startContinuation?.resume(throwing: err)
            startContinuation = nil
            messageStreamContinuation?.finish(throwing: err)
            messageStreamContinuation = nil
            connection.cancel()
        case .waiting(let error):
            // .waiting means NWConnection can't connect right now and
            // will keep retrying on its own. For our use case (the Mac
            // is either listening or it isn't), an indefinite retry
            // loop floods the kernel with TCP SYN/RST pairs and adds
            // background load while the camera is trying to come up.
            // Surface as an error AND cancel the underlying connection
            // so it stops retrying. The user can reconnect explicitly.
            let err = ConnectionError.waiting(error)
            startContinuation?.resume(throwing: err)
            startContinuation = nil
            messageStreamContinuation?.finish(throwing: err)
            messageStreamContinuation = nil
            connection.cancel()
        case .cancelled:
            messageStreamContinuation?.finish()
            messageStreamContinuation = nil
        default:
            break
        }
    }

    private nonisolated func scheduleRead() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8 * 1024) {
            [weak self] data, _, isComplete, error in
            Task { await self?.handleReceive(data: data, isComplete: isComplete, error: error) }
        }
    }

    private func handleReceive(data: Data?, isComplete: Bool, error: NWError?) {
        if let error {
            messageStreamContinuation?.finish(throwing: ConnectionError.transport(error))
            messageStreamContinuation = nil
            return
        }
        if let data, !data.isEmpty {
            readBuffer.append(data)
            drainLines()
        }
        if isComplete {
            messageStreamContinuation?.finish()
            messageStreamContinuation = nil
            return
        }
        scheduleRead()
    }

    private func drainLines() {
        let newline: UInt8 = 0x0A
        while let nlIdx = readBuffer.firstIndex(of: newline) {
            let lineData = readBuffer.subdata(in: readBuffer.startIndex..<nlIdx)
            readBuffer.removeSubrange(readBuffer.startIndex...nlIdx)
            guard !lineData.isEmpty else { continue }
            do {
                let msg = try JSONDecoder().decode(ServerMessage.self, from: lineData)
                messageStreamContinuation?.yield(msg)
            } catch {
                messageStreamContinuation?.finish(
                    throwing: ConnectionError.decoding(error.localizedDescription)
                )
                messageStreamContinuation = nil
                connection.cancel()
                return
            }
        }
    }
}
