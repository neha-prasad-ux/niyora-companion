#if NIYORA_V1_PPG_ENABLED
import XCTest
@testable import NiyoraCompanion

/// Tests for `MeasurementController`'s state machine.
///
/// LIMITATIONS:
///
/// `MeasurementController` is tightly coupled to real platform services ·
/// it constructs a `PPGCapture` (AVFoundation back camera + torch) and a
/// `UIImpactFeedbackGenerator` internally, and `start()` immediately tries
/// to bring up an `AVCaptureSession`. There is no injection seam for a
/// mock capture, so `start()` cannot run in a unit-test process without a
/// camera. We test what is reachable: the public init, the initial state,
/// the unconditional `.idle` → cancel path, and the side-effect of
/// `cancel()` on a fresh controller (produces a `.cancelled` finished
/// result without ever talking to the camera).
///
/// TODO: To test the full state machine (preparing → placingFinger →
/// readyCountdown → capturing → finished), production code would need a
/// `PPGCaptureProtocol` injectable surface so the test can drive the
/// frame callback manually. That is out of scope here per the task
/// constraints (do not modify production source).
@MainActor
final class MeasurementControllerTests: XCTestCase {

    // MARK: - Initial state

    func test_initialState_isIdle() {
        let c = MeasurementController(
            sessionId: "sess-1",
            phase: .pre,
            techniqueName: "Box Breath"
        )
        if case .idle = c.state {
            // ok
        } else {
            XCTFail("expected .idle, got \(c.state)")
        }
    }

    func test_initialState_metadataPropagated() {
        let c = MeasurementController(
            sessionId: "sess-abc",
            phase: .post,
            techniqueName: "4-7-8 Breath",
            isStandalone: true
        )
        XCTAssertEqual(c.sessionId, "sess-abc")
        XCTAssertEqual(c.phase, .post)
        XCTAssertEqual(c.techniqueName, "4-7-8 Breath")
        XCTAssertTrue(c.isStandalone)
        XCTAssertEqual(c.previewSignal, [])
        XCTAssertFalse(c.fingerOnLens)
        XCTAssertNil(c.heartRateBpm)
    }

    func test_initialState_defaultStandaloneFalse() {
        let c = MeasurementController(
            sessionId: "s",
            phase: .pre,
            techniqueName: ""
        )
        XCTAssertFalse(c.isStandalone)
    }

    // MARK: - Cancel from idle

    func test_cancel_fromIdle_producesCancelledFinishedState() {
        let c = MeasurementController(
            sessionId: "sess-x",
            phase: .pre,
            techniqueName: "Box"
        )
        c.cancel()
        guard case let .finished(result) = c.state else {
            XCTFail("expected .finished after cancel from idle, got \(c.state)")
            return
        }
        XCTAssertEqual(result.status, .cancelled)
        XCTAssertNil(result.rmssdMs)
        XCTAssertNil(result.sdnnMs)
        XCTAssertEqual(result.sampleCount, 0)
        XCTAssertNil(result.snrDb)
    }

    func test_cancel_isIdempotent() {
        let c = MeasurementController(
            sessionId: "sess-x",
            phase: .pre,
            techniqueName: "Box"
        )
        c.cancel()
        let snapshot1 = c.state
        c.cancel()
        // The second cancel sees the finished state and bails out without
        // overwriting it (per the guard in cancel()).
        XCTAssertEqual(snapshot1, c.state)
        if case let .finished(r) = c.state {
            XCTAssertEqual(r.status, .cancelled)
        } else {
            XCTFail("expected .finished, got \(c.state)")
        }
    }

    // MARK: - State equality (covers all variants we care about)

    func test_stateEquality_distinguishesVariants() {
        let r1 = PPGMeasurementResult(
            rmssdMs: nil, sdnnMs: nil, sampleCount: 0, snrDb: nil, status: .cancelled
        )
        let r2 = PPGMeasurementResult(
            rmssdMs: 42, sdnnMs: 50, sampleCount: 20, snrDb: 10, status: .ok
        )
        XCTAssertEqual(MeasurementController.State.idle, .idle)
        XCTAssertNotEqual(MeasurementController.State.idle, .preparing)
        XCTAssertEqual(
            MeasurementController.State.readyCountdown(remaining: 2.0),
            MeasurementController.State.readyCountdown(remaining: 2.0)
        )
        XCTAssertNotEqual(
            MeasurementController.State.readyCountdown(remaining: 2.0),
            MeasurementController.State.readyCountdown(remaining: 1.0)
        )
        XCTAssertEqual(
            MeasurementController.State.capturing(elapsed: 5.0),
            MeasurementController.State.capturing(elapsed: 5.0)
        )
        XCTAssertEqual(
            MeasurementController.State.finished(r1),
            MeasurementController.State.finished(r1)
        )
        XCTAssertNotEqual(
            MeasurementController.State.finished(r1),
            MeasurementController.State.finished(r2)
        )
        XCTAssertEqual(
            MeasurementController.State.failed("nope"),
            MeasurementController.State.failed("nope")
        )
        XCTAssertNotEqual(
            MeasurementController.State.failed("a"),
            MeasurementController.State.failed("b")
        )
    }

    // MARK: - Static config

    func test_captureDuration_isThirtySeconds() {
        // Per the spec · locked at 30s. Surfaces as a regression alarm if
        // someone changes it without remembering the wire contract.
        XCTAssertEqual(MeasurementController.captureDurationSec, 30.0)
    }
}
#else
import XCTest

/// PPG-gated · stub when the flag is off.
final class MeasurementControllerTests: XCTestCase {
    func test_ppgDisabled_noop() {
        XCTAssertTrue(true)
    }
}
#endif
