import XCTest
@testable import NiyoraCompanion

/// Wire-protocol v2 frame tests. Each frame type that has an encode
/// (ClientMessage) or decode (ServerMessage) path is exercised
/// encode → JSON bytes → decode → equal. Bad inputs (wrong/missing
/// type, truncated JSON) verify the parser refuses to silently accept.
final class ProtocolTests: XCTestCase {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - ClientMessage (encode-only on this side)
    //
    // The phone is the encoder for ClientMessage. The Mac is the
    // decoder. To avoid bringing the Mac's Rust types into the test we
    // inspect the JSON object directly.

    private func jsonObject(_ msg: ClientMessage) throws -> [String: Any] {
        let data = try encoder.encode(msg)
        let any = try JSONSerialization.jsonObject(with: data)
        return any as? [String: Any] ?? [:]
    }

    func test_clientMessage_identify_encodesAllFields() throws {
        let msg = ClientMessage.identify(
            clientId: "client-123",
            clientName: "Neha's iPhone",
            pairingId: "pair-abc"
        )
        let obj = try jsonObject(msg)

        XCTAssertEqual(obj["type"]        as? String, "identify")
        XCTAssertEqual(obj["protocol"]    as? UInt32, 2)
        XCTAssertEqual(obj["client_id"]   as? String, "client-123")
        XCTAssertEqual(obj["client_name"] as? String, "Neha's iPhone")
        XCTAssertEqual(obj["pairing_id"]  as? String, "pair-abc")
    }

    func test_clientMessage_identify_omitsPairingIdWhenNil() throws {
        let msg = ClientMessage.identify(
            clientId: "client-123",
            clientName: "Neha's iPhone",
            pairingId: nil
        )
        let obj = try jsonObject(msg)

        XCTAssertEqual(obj["type"] as? String, "identify")
        XCTAssertNil(obj["pairing_id"], "encodeIfPresent should drop nil pairing_id")
    }

    func test_clientMessage_auth_encodesHmac() throws {
        let msg = ClientMessage.auth(hmacHex: "deadbeef")
        let obj = try jsonObject(msg)
        XCTAssertEqual(obj["type"]     as? String, "auth")
        XCTAssertEqual(obj["hmac_hex"] as? String, "deadbeef")
    }

    func test_clientMessage_hrvResult_ok_encodesAllMetrics() throws {
        let msg = ClientMessage.hrvResult(
            sessionId: "sess-1",
            phase: .pre,
            rmssdMs: 42.5,
            sdnnMs: 55.0,
            sampleCount: 60,
            snrDb: 12.3,
            status: .ok
        )
        let obj = try jsonObject(msg)

        XCTAssertEqual(obj["type"]         as? String, "hrv_result")
        XCTAssertEqual(obj["session_id"]   as? String, "sess-1")
        XCTAssertEqual(obj["phase"]        as? String, "pre")
        XCTAssertEqual(obj["rmssd_ms"]     as? Double, 42.5)
        XCTAssertEqual(obj["sdnn_ms"]      as? Double, 55.0)
        XCTAssertEqual(obj["sample_count"] as? UInt32, 60)
        XCTAssertEqual(obj["snr_db"]       as? Double, 12.3)
        XCTAssertEqual(obj["status"]       as? String, "ok")
    }

    func test_clientMessage_hrvResult_lowSignal_omitsNilOptionals() throws {
        let msg = ClientMessage.hrvResult(
            sessionId: "sess-1",
            phase: .post,
            rmssdMs: nil,
            sdnnMs: nil,
            sampleCount: 0,
            snrDb: nil,
            status: .lowSignal
        )
        let obj = try jsonObject(msg)

        XCTAssertEqual(obj["type"]   as? String, "hrv_result")
        XCTAssertEqual(obj["phase"]  as? String, "post")
        XCTAssertEqual(obj["status"] as? String, "low_signal")
        XCTAssertNil(obj["rmssd_ms"], "nil rmssd should be omitted")
        XCTAssertNil(obj["sdnn_ms"],  "nil sdnn should be omitted")
        XCTAssertNil(obj["snr_db"],   "nil snr should be omitted")
        // sample_count is non-optional, so it must always be present.
        XCTAssertEqual(obj["sample_count"] as? UInt32, 0)
    }

    // MARK: - ServerMessage (decode-only on this side)

    private func decode(_ json: String) throws -> ServerMessage {
        try decoder.decode(ServerMessage.self, from: Data(json.utf8))
    }

    func test_serverMessage_hello_decodes() throws {
        let json = #"{"type":"hello","server_id":"srv-1","server_name":"Neha's Mac"}"#
        let msg = try decode(json)
        XCTAssertEqual(msg, .hello(serverId: "srv-1", serverName: "Neha's Mac"))
    }

    func test_serverMessage_challenge_decodes() throws {
        let json = #"{"type":"challenge","nonce_hex":"abcd1234"}"#
        let msg = try decode(json)
        XCTAssertEqual(msg, .challenge(nonceHex: "abcd1234"))
    }

    func test_serverMessage_authed_decodes() throws {
        let json = #"{"type":"authed"}"#
        let msg = try decode(json)
        XCTAssertEqual(msg, .authed)
    }

    func test_serverMessage_authFailed_decodes() throws {
        let json = #"{"type":"auth_failed","reason":"bad_hmac"}"#
        let msg = try decode(json)
        XCTAssertEqual(msg, .authFailed(reason: "bad_hmac"))
    }

    func test_serverMessage_requestMeasurement_decodes() throws {
        let json = #"{"type":"request_measurement","session_id":"sess-9","phase":"pre","technique_name":"Box Breathing"}"#
        let msg = try decode(json)
        XCTAssertEqual(
            msg,
            .requestMeasurement(sessionId: "sess-9", phase: .pre, techniqueName: "Box Breathing")
        )
    }

    func test_serverMessage_requestMeasurement_postPhase_decodes() throws {
        let json = #"{"type":"request_measurement","session_id":"s","phase":"post","technique_name":"4-7-8"}"#
        let msg = try decode(json)
        XCTAssertEqual(msg, .requestMeasurement(sessionId: "s", phase: .post, techniqueName: "4-7-8"))
    }

    // MARK: - Bad inputs

    func test_serverMessage_unknownType_throws() {
        let json = #"{"type":"definitely_not_a_real_type"}"#
        XCTAssertThrowsError(try decode(json))
    }

    func test_serverMessage_missingType_throws() {
        let json = #"{"server_id":"srv","server_name":"Mac"}"#
        XCTAssertThrowsError(try decode(json))
    }

    func test_serverMessage_truncatedJson_throws() {
        let json = #"{"type":"hello","server_id":"srv-1""#  // missing closing brace
        XCTAssertThrowsError(try decode(json))
    }

    func test_serverMessage_helloMissingRequiredField_throws() {
        // Missing server_name.
        let json = #"{"type":"hello","server_id":"srv-1"}"#
        XCTAssertThrowsError(try decode(json))
    }

    func test_serverMessage_requestMeasurementBadPhase_throws() {
        let json = #"{"type":"request_measurement","session_id":"s","phase":"middle","technique_name":"x"}"#
        XCTAssertThrowsError(try decode(json))
    }

    // MARK: - Hex helpers (used by the auth path)

    func test_hex_encodeDecodeRoundTrip() {
        let data = Data([0x00, 0x01, 0xFE, 0xFF, 0xAB])
        let hex = Hex.encode(data)
        XCTAssertEqual(hex, "0001feffab")
        XCTAssertEqual(Hex.decode(hex), data)
    }

    func test_hex_decodeOddLength_returnsNil() {
        XCTAssertNil(Hex.decode("abc"))
    }

    func test_hex_decodeNonHex_returnsNil() {
        XCTAssertNil(Hex.decode("zz"))
    }

    func test_hex_decodeEmpty_returnsEmpty() {
        XCTAssertEqual(Hex.decode(""), Data())
    }
}
