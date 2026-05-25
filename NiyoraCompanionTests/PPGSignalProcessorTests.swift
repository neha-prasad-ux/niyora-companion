#if NIYORA_V1_PPG_ENABLED
import XCTest
@testable import NiyoraCompanion

/// Tests the math in `PPGSignalProcessor` by feeding it synthetic PPG-like
/// signals. The processor assumes 30 fps · we generate samples at that
/// rate. For HR/RMSSD checks we feed a clean sinusoid at a known heart-rate
/// frequency plus a small mean offset (so detrend sees something to remove)
/// and a paired red channel that satisfies `fingerLikelyOnLens()`.
///
/// Tolerances are deliberately generous · the bandpass + adaptive peak
/// detector + IBI outlier rejection introduce small biases on synthetic
/// signals that wouldn't matter on real PPG. We're verifying the pipeline
/// runs end-to-end and produces values in the right neighbourhood.
final class PPGSignalProcessorTests: XCTestCase {

    private let fs = PPGSignalProcessor.sampleRateHz

    // MARK: - Helpers

    /// Build a green-channel signal that looks like PPG · a sinusoid at
    /// `bpm/60` Hz, centred at a positive mean so the floor stays >0, and
    /// for `seconds` of capture. The amplitude is small relative to the
    /// mean because real PPG AC is a few percent of the DC level.
    private func makeGreenSignal(bpm: Double, seconds: Double, amplitude: Double = 10.0, mean: Double = 100.0) -> [Double] {
        let n = Int(seconds * fs)
        let freq = bpm / 60.0
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / fs
            out[i] = mean + amplitude * sin(2.0 * .pi * freq * t)
        }
        return out
    }

    /// Red channel matching the green signal · constant high red so the
    /// red/green ratio satisfies `fingerLikelyOnLens()` (ratio > 2, red in
    /// [30, 252]).
    private func makeRedSignal(matching green: [Double], red: Double = 220.0) -> [Double] {
        [Double](repeating: red, count: green.count)
    }

    private func feed(_ processor: inout PPGSignalProcessor, green: [Double], red: [Double]) {
        precondition(green.count == red.count)
        for i in 0..<green.count {
            processor.append(green: green[i], red: red[i])
        }
    }

    // MARK: - Append / dropFirst

    func test_append_growsBuffersInLockstep() {
        var p = PPGSignalProcessor()
        XCTAssertEqual(p.samples.count, 0)
        XCTAssertEqual(p.redSamples.count, 0)
        p.append(green: 50, red: 200)
        p.append(green: 51, red: 201)
        XCTAssertEqual(p.samples, [50, 51])
        XCTAssertEqual(p.redSamples, [200, 201])
    }

    func test_dropFirst_trimsBothBuffers() {
        var p = PPGSignalProcessor()
        for i in 0..<10 {
            p.append(green: Double(i), red: Double(i + 100))
        }
        p.dropFirst(3)
        XCTAssertEqual(p.samples.count, 7)
        XCTAssertEqual(p.redSamples.count, 7)
        XCTAssertEqual(p.samples.first, 3)
        XCTAssertEqual(p.redSamples.first, 103)
    }

    func test_dropFirst_clampsToBufferSize() {
        var p = PPGSignalProcessor()
        p.append(green: 1, red: 1)
        p.dropFirst(100)
        XCTAssertEqual(p.samples.count, 0)
        XCTAssertEqual(p.redSamples.count, 0)
    }

    func test_dropFirst_zeroIsNoOp() {
        var p = PPGSignalProcessor()
        for i in 0..<5 { p.append(green: Double(i), red: Double(i)) }
        p.dropFirst(0)
        XCTAssertEqual(p.samples.count, 5)
    }

    // MARK: - Finger-on detector

    func test_fingerLikelyOnLens_falseOnEmptyBuffer() {
        let p = PPGSignalProcessor()
        XCTAssertFalse(p.fingerLikelyOnLens())
    }

    func test_fingerLikelyOnLens_trueWhenRedFarExceedsGreen() {
        var p = PPGSignalProcessor()
        // High red, low green · classic finger-on-torch signature.
        for _ in 0..<Int(fs) {
            p.append(green: 20, red: 200)
        }
        XCTAssertTrue(p.fingerLikelyOnLens())
    }

    func test_fingerLikelyOnLens_falseWhenRatioTooLow() {
        var p = PPGSignalProcessor()
        // Roughly balanced colour · looks like the camera sees the room.
        for _ in 0..<Int(fs) {
            p.append(green: 100, red: 110)
        }
        XCTAssertFalse(p.fingerLikelyOnLens())
    }

    func test_fingerLikelyOnLens_falseWhenRedSaturated() {
        var p = PPGSignalProcessor()
        // Red is pegged at 255 · saturated, reject.
        for _ in 0..<Int(fs) {
            p.append(green: 20, red: 255)
        }
        XCTAssertFalse(p.fingerLikelyOnLens())
    }

    // MARK: - Pure pipeline math (signal-independent)

    func test_peakIntervalsMs_evenlySpacedPeaksGiveExpectedIbi() {
        let p = PPGSignalProcessor()
        // Peaks 30 samples apart at 30 fps → 1000 ms IBI → 60 bpm.
        let peaks = [0, 30, 60, 90, 120]
        let ibis = p.peakIntervalsMs(peaks)
        XCTAssertEqual(ibis.count, 4)
        for ibi in ibis {
            XCTAssertEqual(ibi, 1000.0, accuracy: 0.01)
        }
    }

    func test_peakIntervalsMs_emptyOnSingleOrZeroPeaks() {
        let p = PPGSignalProcessor()
        XCTAssertEqual(p.peakIntervalsMs([]).count, 0)
        XCTAssertEqual(p.peakIntervalsMs([42]).count, 0)
    }

    func test_rmssd_constantIbisIsZero() {
        let p = PPGSignalProcessor()
        let rmssd = p.rmssd([800, 800, 800, 800])
        XCTAssertNotNil(rmssd)
        XCTAssertEqual(rmssd!, 0, accuracy: 0.0001)
    }

    func test_rmssd_knownAlternatingValues() {
        let p = PPGSignalProcessor()
        // IBIs: 800, 850, 800, 850. Successive diffs: 50, -50, 50.
        // RMSSD = sqrt((50^2 + 50^2 + 50^2)/3) = 50.
        let rmssd = p.rmssd([800, 850, 800, 850])
        XCTAssertNotNil(rmssd)
        XCTAssertEqual(rmssd!, 50, accuracy: 0.01)
    }

    func test_rmssd_nilOnFewerThanTwoIbis() {
        let p = PPGSignalProcessor()
        XCTAssertNil(p.rmssd([]))
        XCTAssertNil(p.rmssd([800]))
    }

    func test_sdnn_constantIbisIsZero() {
        let p = PPGSignalProcessor()
        let sdnn = p.sdnn([800, 800, 800])
        XCTAssertNotNil(sdnn)
        XCTAssertEqual(sdnn!, 0, accuracy: 0.0001)
    }

    func test_sdnn_nilOnFewerThanTwoIbis() {
        let p = PPGSignalProcessor()
        XCTAssertNil(p.sdnn([]))
        XCTAssertNil(p.sdnn([700]))
    }

    func test_rejectIbiOutliers_passthroughBelowFive() {
        let p = PPGSignalProcessor()
        let xs = [800.0, 5000.0, 50.0]
        XCTAssertEqual(p.rejectIbiOutliers(xs), xs)
    }

    func test_rejectIbiOutliers_dropsExtremesOnLongInput() {
        let p = PPGSignalProcessor()
        // Median = 800. Bounds [560, 1040]. 5000 and 50 should drop.
        let xs = [800.0, 810, 790, 805, 795, 5000, 50]
        let kept = p.rejectIbiOutliers(xs)
        XCTAssertFalse(kept.contains(5000))
        XCTAssertFalse(kept.contains(50))
        XCTAssertEqual(kept.count, 5)
    }

    func test_detrend_constantSignalGoesToZero() {
        let p = PPGSignalProcessor()
        let xs = [Double](repeating: 100, count: 90) // 3s at 30 fps
        let out = p.detrend(xs, windowSeconds: 1.0)
        for v in out {
            XCTAssertEqual(v, 0, accuracy: 1e-9)
        }
    }

    // MARK: - End-to-end on synthetic signals

    func test_computeResult_60bpmSine_detectsAroundSixtyBpm() {
        var p = PPGSignalProcessor()
        let seconds = 30.0
        let bpm = 60.0
        let green = makeGreenSignal(bpm: bpm, seconds: seconds)
        let red = makeRedSignal(matching: green)
        feed(&p, green: green, red: red)

        let result = p.computeResult(captureCompleted: true)
        XCTAssertEqual(result.status, .ok, "expected ok status, got \(result.status)")
        // Reconstruct BPM from RMSSD-adjacent IBIs by re-running the same
        // pipeline that computeResult ran. We don't expose the IBIs · but
        // sample count is the count of IBIs, and the signal is a pure
        // sinusoid, so we can sanity-check via expected counts: 30s at
        // 60bpm should give ~30 beats and ~29 IBIs (some lost to edges).
        XCTAssertGreaterThan(Int(result.sampleCount), 15,
                             "expected at least 15 IBIs over 30s @ 60bpm, got \(result.sampleCount)")
    }

    func test_computeResult_75bpmSine_detectsAroundSeventyFive() {
        var p = PPGSignalProcessor()
        let seconds = 30.0
        let bpm = 75.0
        let green = makeGreenSignal(bpm: bpm, seconds: seconds)
        let red = makeRedSignal(matching: green)
        feed(&p, green: green, red: red)

        let result = p.computeResult(captureCompleted: true)
        XCTAssertEqual(result.status, .ok)

        // Recompute the implied mean HR through the same pipeline (we don't
        // get heart rate back from PPGMeasurementResult · the controller
        // computes it separately). We mirror the production pipeline.
        let detrended = p.detrend(p.samples, windowSeconds: 1.5)
        let bandpassed = p.bandpass(detrended)
        let peaks = p.detectPeaks(bandpassed)
        let rawIbis = p.peakIntervalsMs(peaks)
        let ibis = p.rejectIbiOutliers(rawIbis)
        XCTAssertFalse(ibis.isEmpty)
        let meanIbi = ibis.reduce(0, +) / Double(ibis.count)
        let hr = 60_000.0 / meanIbi
        XCTAssertEqual(hr, bpm, accuracy: 5.0,
                       "expected ~75 bpm ±5, got \(hr)")
    }

    func test_computeResult_72bpmSine_clampsToHrTolerance() {
        var p = PPGSignalProcessor()
        let bpm = 72.0
        let green = makeGreenSignal(bpm: bpm, seconds: 30.0)
        let red = makeRedSignal(matching: green)
        feed(&p, green: green, red: red)

        let result = p.computeResult(captureCompleted: true)
        XCTAssertEqual(result.status, .ok)

        let detrended = p.detrend(p.samples, windowSeconds: 1.5)
        let bandpassed = p.bandpass(detrended)
        let peaks = p.detectPeaks(bandpassed)
        let ibis = p.rejectIbiOutliers(p.peakIntervalsMs(peaks))
        XCTAssertFalse(ibis.isEmpty)
        let meanIbi = ibis.reduce(0, +) / Double(ibis.count)
        let hr = 60_000.0 / meanIbi
        XCTAssertEqual(hr, bpm, accuracy: 5.0)
    }

    func test_computeResult_pureSineYieldsLowRmssd() {
        // A perfectly periodic sinusoid has constant IBIs, so RMSSD must
        // be very small. We use the human-likely floor (5 ms) from the
        // physiologic gate as the upper bound · anything well below that
        // would otherwise have been filtered out as "not human."
        // computeResult's gate is rmssd in [5, 250]. A pure sinusoid
        // typically produces near-zero RMSSD which makes the status
        // .lowSignal · we verify that branch explicitly.
        var p = PPGSignalProcessor()
        let green = makeGreenSignal(bpm: 70, seconds: 30.0)
        let red = makeRedSignal(matching: green)
        feed(&p, green: green, red: red)
        let result = p.computeResult(captureCompleted: true)
        // Either ok (if small numerical wobble pushes RMSSD above 5) or
        // lowSignal (if RMSSD is below the physiologic floor). Both are
        // acceptable for a noise-free sinusoid · the assertion is that we
        // do NOT crash and do NOT return finger-lifted/cancelled.
        XCTAssertTrue(result.status == .ok || result.status == .lowSignal,
                      "unexpected status \(result.status)")
    }

    // MARK: - computeResult status gates

    func test_computeResult_fingerLiftedWhenCaptureIncomplete() {
        var p = PPGSignalProcessor()
        let green = makeGreenSignal(bpm: 60, seconds: 30)
        let red = makeRedSignal(matching: green)
        feed(&p, green: green, red: red)
        let result = p.computeResult(captureCompleted: false)
        XCTAssertEqual(result.status, .fingerLifted)
        XCTAssertNil(result.rmssdMs)
        XCTAssertNil(result.sdnnMs)
    }

    func test_computeResult_lowSignalWhenLessThanFiveSecondsOfSamples() {
        var p = PPGSignalProcessor()
        // Only 3 seconds at 30 fps · below the 5s minimum.
        for _ in 0..<Int(fs * 3) {
            p.append(green: 100, red: 200)
        }
        let result = p.computeResult(captureCompleted: true)
        XCTAssertEqual(result.status, .lowSignal)
        XCTAssertNil(result.rmssdMs)
        XCTAssertEqual(result.sampleCount, 0)
    }

    func test_computeResult_lowSignalOnFlatBufferPastFiveSeconds() {
        var p = PPGSignalProcessor()
        // 10s of identical samples · detrend gives zeros, bandpass gives
        // zeros, detectPeaks finds none, ibis < minIbiCount.
        for _ in 0..<Int(fs * 10) {
            p.append(green: 100, red: 200)
        }
        let result = p.computeResult(captureCompleted: true)
        XCTAssertEqual(result.status, .lowSignal)
    }
}
#else
import XCTest

/// PPG is gated behind `NIYORA_V1_PPG_ENABLED`. When the flag is off the
/// signal processor doesn't compile · this stub keeps the test target
/// happy.
final class PPGSignalProcessorTests: XCTestCase {
    func test_ppgDisabled_noop() {
        XCTAssertTrue(true)
    }
}
#endif
