import XCTest
@testable import NiyoraCompanion

/// Codable round-trips for the model types in `Models.swift`. The
/// shipping path encodes these into the v2 wire frames, so a regression
/// in raw-value spelling would silently break Mac compatibility.
final class ModelsTests: XCTestCase {
    // MARK: - MeasurementPhase

    func test_measurementPhase_encodesToKnownRawValues() throws {
        let encoder = JSONEncoder()
        let preData  = try encoder.encode(MeasurementPhase.pre)
        let postData = try encoder.encode(MeasurementPhase.post)

        // JSONEncoder wraps the raw value in quotes.
        XCTAssertEqual(String(data: preData,  encoding: .utf8), "\"pre\"")
        XCTAssertEqual(String(data: postData, encoding: .utf8), "\"post\"")
    }

    func test_measurementPhase_decodesFromKnownRawValues() throws {
        let decoder = JSONDecoder()
        let pre  = try decoder.decode(MeasurementPhase.self, from: Data("\"pre\"".utf8))
        let post = try decoder.decode(MeasurementPhase.self, from: Data("\"post\"".utf8))
        XCTAssertEqual(pre,  .pre)
        XCTAssertEqual(post, .post)
    }

    func test_measurementPhase_decodingUnknownThrows() {
        let decoder = JSONDecoder()
        XCTAssertThrowsError(try decoder.decode(MeasurementPhase.self, from: Data("\"middle\"".utf8)))
    }

    func test_measurementPhase_roundTrip() throws {
        for value in [MeasurementPhase.pre, .post] {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(MeasurementPhase.self, from: data)
            XCTAssertEqual(decoded, value)
        }
    }

    // MARK: - HrvResultStatus (lives in Protocol.swift but is the canonical
    // status enum the models hand around; covered here for completeness.)

    func test_hrvResultStatus_rawValues() throws {
        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(HrvResultStatus.self, from: Data("\"ok\"".utf8)),            .ok)
        XCTAssertEqual(try decoder.decode(HrvResultStatus.self, from: Data("\"low_signal\"".utf8)),    .lowSignal)
        XCTAssertEqual(try decoder.decode(HrvResultStatus.self, from: Data("\"finger_lifted\"".utf8)), .fingerLifted)
        XCTAssertEqual(try decoder.decode(HrvResultStatus.self, from: Data("\"cancelled\"".utf8)),     .cancelled)
    }

    func test_hrvResultStatus_roundTrip() throws {
        let all: [HrvResultStatus] = [.ok, .lowSignal, .fingerLifted, .cancelled]
        for s in all {
            let data = try JSONEncoder().encode(s)
            let decoded = try JSONDecoder().decode(HrvResultStatus.self, from: data)
            XCTAssertEqual(decoded, s)
        }
    }

    // MARK: - KnownServer

    func test_knownServer_codableRoundTrip() throws {
        let server = KnownServer(
            serverId: UUID().uuidString,
            serverName: "Neha's Mac",
            host: "192.168.1.42",
            port: 51820
        )

        let data = try JSONEncoder().encode(server)
        let decoded = try JSONDecoder().decode(KnownServer.self, from: data)
        XCTAssertEqual(decoded, server)
        XCTAssertEqual(decoded.id, server.serverId, "Identifiable.id should mirror serverId")
    }

    // MARK: - QrPayload (Codable + base64-url round trip)

    func test_qrPayload_codableRoundTrip() throws {
        let payload = QrPayload(
            v: 2,
            serverId: "server-abc",
            serverName: "Neha's Mac",
            host: "10.0.0.5",
            port: 51820,
            pairingId: "pair-xyz",
            secretHex: "deadbeefcafebabe"
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(QrPayload.self, from: data)
        XCTAssertEqual(decoded, payload)
    }

    func test_qrPayload_base64UrlRoundTrip() throws {
        let payload = QrPayload(
            v: 2,
            serverId: "srv",
            serverName: "Mac",
            host: "10.0.0.1",
            port: 51820,
            pairingId: "pid",
            secretHex: "00ff"
        )

        let encoded = payload.encode()
        XCTAssertNotNil(encoded)
        // base64-url has no padding and no + or /.
        if let s = encoded {
            XCTAssertFalse(s.contains("="))
            XCTAssertFalse(s.contains("+"))
            XCTAssertFalse(s.contains("/"))
        }

        let decoded = QrPayload.decode(encoded!)
        XCTAssertEqual(decoded, payload)
    }

    func test_qrPayload_decodeRejectsGarbage() {
        XCTAssertNil(QrPayload.decode("not a valid base64url!"))
        XCTAssertNil(QrPayload.decode(""))
    }
}
