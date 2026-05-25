import Foundation

/// Wire protocol v2 between Niyora Companion (iPhone) and Niyora (Mac).
///
/// NDJSON over TCP, one JSON object per line. Each frame carries a
/// `type` discriminator. Unknown types are fatal on both sides ‑ a
/// confused peer is more dangerous than a clean disconnect.
///
/// Lifecycle from the phone's perspective:
///
///     →  identify             { client_id, client_name, pairing_id? }
///     ←  hello                { server_id, server_name }
///     ←  challenge            { nonce_hex }
///     →  auth                 { hmac_hex }                  // HMAC-SHA256(secret, nonce)
///     ←  authed   or   ← auth_failed (then close)
///     ←  request_measurement  { session_id, phase, technique_name }   (zero or more per session)
///
/// `pairing_id` is set only on the first connect after the user scans a
/// fresh QR. On every subsequent reconnect it is absent and the Mac looks
/// up the secret by `client_id`.
///
/// v2 vs v1: the HealthKit-on-window auto-read path is gone. Sessions no
/// longer auto-emit a window at end. The Mac now sends one
/// `request_measurement` per "Measure stress" tap (phase = "pre" or
/// "post"). The phone responds with `hrv_result` once it has computed
/// RMSSD + SDNN from a 30s green-channel PPG capture.
enum WireProtocol {
    static let version: UInt32 = 2
}

// MARK: - Client → Mac

enum ClientMessage: Encodable, Equatable {
    case identify(clientId: String, clientName: String, pairingId: String?)
    case auth(hmacHex: String)
    /// One per-phase PPG capture the phone produced for a session. The
    /// Mac merges `pre` and `post` frames sharing the same `sessionId`
    /// into a single history row.
    case hrvResult(
        sessionId: String,
        phase: MeasurementPhase,
        rmssdMs: Double?,
        sdnnMs: Double?,
        sampleCount: UInt32,
        snrDb: Double?,
        status: HrvResultStatus
    )

    enum CodingKeys: String, CodingKey {
        case type
        case protocolVersion = "protocol"
        case clientId = "client_id"
        case clientName = "client_name"
        case pairingId = "pairing_id"
        case hmacHex = "hmac_hex"
        case sessionId = "session_id"
        case phase
        case rmssdMs = "rmssd_ms"
        case sdnnMs = "sdnn_ms"
        case sampleCount = "sample_count"
        case snrDb = "snr_db"
        case status
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .identify(clientId, clientName, pairingId):
            try c.encode("identify", forKey: .type)
            try c.encode(WireProtocol.version, forKey: .protocolVersion)
            try c.encode(clientId, forKey: .clientId)
            try c.encode(clientName, forKey: .clientName)
            try c.encodeIfPresent(pairingId, forKey: .pairingId)
        case let .auth(hmacHex):
            try c.encode("auth", forKey: .type)
            try c.encode(hmacHex, forKey: .hmacHex)
        case let .hrvResult(sessionId, phase, rmssdMs, sdnnMs, sampleCount, snrDb, status):
            try c.encode("hrv_result", forKey: .type)
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(phase.rawValue, forKey: .phase)
            try c.encodeIfPresent(rmssdMs, forKey: .rmssdMs)
            try c.encodeIfPresent(sdnnMs, forKey: .sdnnMs)
            try c.encode(sampleCount, forKey: .sampleCount)
            try c.encodeIfPresent(snrDb, forKey: .snrDb)
            try c.encode(status.rawValue, forKey: .status)
        }
    }
}

/// Status the phone reports about a capture. `ok` means RMSSD and SDNN
/// are present and trustworthy; the other variants explain why they are
/// nil. The Mac forwards these into the per-phase history row so users
/// see "low signal, try again" rather than a fabricated number.
enum HrvResultStatus: String, Codable, Equatable {
    case ok
    case lowSignal = "low_signal"
    case fingerLifted = "finger_lifted"
    case cancelled
}

// MARK: - Mac → Client

enum ServerMessage: Decodable, Equatable {
    /// `currentTier` and `totalSessionCount` are optional: older Mac
    /// builds omit them; newer builds include them for paired-mode tier
    /// display on the phone.
    case hello(serverId: String, serverName: String, currentTier: String?, totalSessionCount: Int?)
    case challenge(nonceHex: String)
    case authed
    case authFailed(reason: String)
    /// Mac asks the phone to start a 30s PPG capture for one side of a
    /// session. Emitted only after a user "Measure stress" tap, never
    /// automatically. Idempotent on (sessionId, phase) · the phone
    /// dedupes if the same request arrives twice across a reconnect.
    case requestMeasurement(sessionId: String, phase: MeasurementPhase, techniqueName: String)

    enum CodingKeys: String, CodingKey {
        case type
        case serverId = "server_id"
        case serverName = "server_name"
        case currentTier = "current_tier"
        case totalSessionCount = "total_session_count"
        case nonceHex = "nonce_hex"
        case reason
        case sessionId = "session_id"
        case phase
        case techniqueName = "technique_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "hello":
            self = .hello(
                serverId: try c.decode(String.self, forKey: .serverId),
                serverName: try c.decode(String.self, forKey: .serverName),
                currentTier: try c.decodeIfPresent(String.self, forKey: .currentTier),
                totalSessionCount: try c.decodeIfPresent(Int.self, forKey: .totalSessionCount)
            )
        case "challenge":
            self = .challenge(nonceHex: try c.decode(String.self, forKey: .nonceHex))
        case "authed":
            self = .authed
        case "auth_failed":
            self = .authFailed(reason: try c.decode(String.self, forKey: .reason))
        case "request_measurement":
            self = .requestMeasurement(
                sessionId: try c.decode(String.self, forKey: .sessionId),
                phase: try c.decode(MeasurementPhase.self, forKey: .phase),
                techniqueName: try c.decode(String.self, forKey: .techniqueName)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: c,
                debugDescription: "Unknown server message type: \(type)"
            )
        }
    }
}

// MARK: - QR payload

/// Base64-URL-no-pad JSON encoded in the pairing QR. Single use ‑ the Mac
/// invalidates `pairingId` on the first successful HMAC verification, so
/// a glimpsed code is useless to a bystander who can't outpace the user
/// to the network handshake.
struct QrPayload: Codable, Equatable {
    let v: UInt32
    let serverId: String
    let serverName: String
    let host: String
    let port: UInt16
    let pairingId: String
    let secretHex: String

    enum CodingKeys: String, CodingKey {
        case v
        case serverId = "server_id"
        case serverName = "server_name"
        case host, port
        case pairingId = "pairing_id"
        case secretHex = "secret_hex"
    }

    /// Decode the base64-url string that comes out of the QR scanner.
    static func decode(_ base64UrlString: String) -> QrPayload? {
        guard let data = Self.base64UrlDecode(base64UrlString) else { return nil }
        return try? JSONDecoder().decode(QrPayload.self, from: data)
    }

    /// Inverse, included so the iOS unit tests can round-trip without
    /// reaching for the Mac side.
    func encode() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return Self.base64UrlEncode(data)
    }

    private static func base64UrlDecode(_ s: String) -> Data? {
        var b64 = s
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Restore padding ‑ base64-url-no-pad strips it.
        let pad = (4 - b64.count % 4) % 4
        b64.append(String(repeating: "=", count: pad))
        return Data(base64Encoded: b64)
    }

    private static func base64UrlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Hex helpers

enum Hex {
    /// Lowercase hex of a Data buffer. Used for nonces and HMAC tags so
    /// the encoded form matches the Mac's `format!("{:02x}", b)` output.
    static func encode(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func decode(_ s: String) -> Data? {
        guard s.count.isMultiple(of: 2) else { return nil }
        var out = Data(capacity: s.count / 2)
        var idx = s.startIndex
        while idx < s.endIndex {
            let next = s.index(idx, offsetBy: 2)
            guard let byte = UInt8(s[idx..<next], radix: 16) else { return nil }
            out.append(byte)
            idx = next
        }
        return out
    }
}
