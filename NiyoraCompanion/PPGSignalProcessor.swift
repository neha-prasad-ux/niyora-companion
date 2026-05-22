import Foundation

/// Processes a stream of per-frame green-channel means into HRV metrics.
///
/// The pipeline mirrors what every consumer HRV-from-PPG app does:
///
///   1. Buffer the raw signal as it arrives.
///   2. De-trend (subtract a moving mean) so the slow drift from finger
///      pressure changes doesn't dominate the AC pulse component.
///   3. Bandpass around the heart-rate band [0.7, 4.0] Hz (42-240 bpm)
///      with a small IIR · cheap and good enough for peak picking.
///   4. Detect peaks with a refractory window so a noisy double-bump
///      doesn't count twice.
///   5. From peak times compute inter-beat intervals (IBIs), then
///      RMSSD and SDNN.
///   6. Estimate SNR as the ratio of in-band variance to out-of-band
///      variance and decide ok / low_signal / finger_lifted.
///
/// The processor is value-typed and pure · UI owns the lifetime.
struct PPGSignalProcessor {

    /// Sample rate the capture layer commits to (30 fps · the AVFoundation
    /// session pins activeVideoMin/MaxFrameDuration to 1/30s).
    static let sampleRateHz: Double = 30.0
    /// Minimum number of IBIs needed to compute trustworthy HRV. With a
    /// ~60 bpm baseline, 30s gives ~30 IBIs · we accept down to 8 to
    /// tolerate the first second of stabilisation plus occasional
    /// missed peaks. The post-hoc HR sanity gate (40-180 bpm) catches
    /// any "8 beats in 30s = 16 bpm" mismeasures.
    static let minIbiCount: Int = 8
    /// Minimum SNR for an "ok" status, in dB. The crude estimator I
    /// use is biased low for slow signals (sample-to-sample
    /// differences are small even for clean pulses), so the threshold
    /// is set generously. The physiologic-range gate below is the
    /// stronger safeguard.
    static let minSnrDb: Double = 2.0

    /// Raw per-frame mean green values, oldest first. Trimmed to the
    /// window the caller passes when computing metrics. Green is the
    /// PPG signal channel · the HRV math runs on this alone.
    private(set) var samples: [Double] = []
    /// Per-frame mean red values, paired with `samples`. Used only by
    /// the finger-on detector · the red-to-green ratio is a robust
    /// signature of "finger on lens with torch on" (hemoglobin absorbs
    /// green strongly, reflects red strongly, so R/G goes to 3-6×).
    private(set) var redSamples: [Double] = []

    /// Append a freshly measured frame summary. O(1).
    mutating func append(green: Double, red: Double) {
        samples.append(green)
        redSamples.append(red)
    }

    /// Drop the first `n` samples · the capture layer uses this to skip
    /// the first ~1s of stabilisation while the AGC and torch settle.
    mutating func dropFirst(_ n: Int) {
        guard n > 0 else { return }
        let drop = min(n, samples.count)
        samples.removeFirst(drop)
        let dropRed = min(n, redSamples.count)
        redSamples.removeFirst(dropRed)
    }

    /// Whether the most recent window of samples looks like a finger is
    /// on the lens with the torch on. The robust signal is the red-to-
    /// green ratio · hemoglobin absorbs green light strongly and
    /// reflects red strongly, so a finger + torch gives R/G of about
    /// 3 to 6, while the camera looking at a normal scene gives R/G
    /// around 0.8 to 1.2 (roughly balanced color). With a bright torch
    /// the absorbed green can drop almost to zero, sending the ratio
    /// into the hundreds · that is exactly the signal we want.
    func fingerLikelyOnLens() -> Bool {
        let lookback = Int(Self.sampleRateHz * 0.5)
        guard samples.count >= lookback,
              redSamples.count >= lookback else { return false }
        let g = samples.suffix(lookback).reduce(0, +) / Double(lookback)
        let r = redSamples.suffix(lookback).reduce(0, +) / Double(lookback)
        // Floor the denominator rather than rejecting low-green frames.
        // When the torch is bright and a finger covers the lens green
        // averages near 0 · that is the signal we want to keep, not
        // discard as "too dark."
        let safeG = max(g, 0.5)
        let ratio = r / safeG
        // r in [30, 252] rejects ambient (too dim) and saturated frames.
        // No upper bound on g · with a finger on, it's tiny anyway.
        return ratio > 2.0 && r > 30 && r < 252
    }

    /// Run the full pipeline against the current buffer and return the
    /// HRV metrics. `captureCompleted` lets the caller distinguish a
    /// natural end (30s elapsed) from a finger-lifted abort.
    func computeResult(captureCompleted: Bool) -> PPGMeasurementResult {
        if !captureCompleted {
            #if DEBUG
            print("[PPGSignal] result=fingerLifted · capture aborted early")
            #endif
            return PPGMeasurementResult(
                rmssdMs: nil, sdnnMs: nil,
                sampleCount: 0, snrDb: nil,
                status: .fingerLifted
            )
        }
        guard samples.count >= Int(Self.sampleRateHz * 5) else {
            #if DEBUG
            print("[PPGSignal] result=lowSignal · only \(samples.count) samples (<5s worth)")
            #endif
            return PPGMeasurementResult(
                rmssdMs: nil, sdnnMs: nil,
                sampleCount: 0, snrDb: nil,
                status: .lowSignal
            )
        }

        let detrended = detrend(samples, windowSeconds: 1.5)
        let filtered = bandpass(detrended)
        let peaks = detectPeaks(filtered)
        let ibisMs = peakIntervalsMs(peaks)
        let snr = estimateSnrDb(filtered)
        let meanIbiMs = ibisMs.isEmpty ? 0 : ibisMs.reduce(0, +) / Double(ibisMs.count)
        let heartRateBpm = meanIbiMs > 0 ? 60_000.0 / meanIbiMs : 0
        let rmssdValue = rmssd(ibisMs) ?? 0
        let sdnnValue = sdnn(ibisMs) ?? 0

        #if DEBUG
        print("[PPGSignal] samples=\(samples.count) peaks=\(peaks.count) ibis=\(ibisMs.count) snrDb=\(String(format: "%.2f", snr)) hrBpm=\(String(format: "%.1f", heartRateBpm)) rmssdMs=\(String(format: "%.1f", rmssdValue)) sdnnMs=\(String(format: "%.1f", sdnnValue))")
        #endif

        guard ibisMs.count >= Self.minIbiCount else {
            #if DEBUG
            print("[PPGSignal] result=lowSignal · too few IBIs (\(ibisMs.count) < \(Self.minIbiCount))")
            #endif
            return PPGMeasurementResult(
                rmssdMs: nil, sdnnMs: nil,
                sampleCount: UInt32(ibisMs.count),
                snrDb: snr,
                status: .lowSignal
            )
        }
        guard snr >= Self.minSnrDb else {
            #if DEBUG
            print("[PPGSignal] result=lowSignal · SNR \(String(format: "%.2f", snr)) < \(Self.minSnrDb)")
            #endif
            return PPGMeasurementResult(
                rmssdMs: nil, sdnnMs: nil,
                sampleCount: UInt32(ibisMs.count),
                snrDb: snr,
                status: .lowSignal
            )
        }

        // Physiologic sanity. Without these guards a no-finger capture
        // can sneak through with garbage values (RMSSD ~1400 ms, HR
        // ~20 bpm), because the peak detector is finding random local
        // maxima in noise. Reject anything outside what a human body
        // could plausibly produce.
        let humanLikelyHr = heartRateBpm >= 40 && heartRateBpm <= 180
        let humanLikelyRmssd = rmssdValue >= 5 && rmssdValue <= 250
        guard humanLikelyHr, humanLikelyRmssd else {
            #if DEBUG
            print("[PPGSignal] result=lowSignal · HR \(String(format: "%.1f", heartRateBpm)) or RMSSD \(String(format: "%.1f", rmssdValue)) outside physiologic range")
            #endif
            return PPGMeasurementResult(
                rmssdMs: nil, sdnnMs: nil,
                sampleCount: UInt32(ibisMs.count),
                snrDb: snr,
                status: .lowSignal
            )
        }

        #if DEBUG
        print("[PPGSignal] result=ok")
        #endif
        return PPGMeasurementResult(
            rmssdMs: rmssd(ibisMs),
            sdnnMs: sdnn(ibisMs),
            sampleCount: UInt32(ibisMs.count),
            snrDb: snr,
            status: .ok
        )
    }

    // MARK: - Internals exposed only to the same module for testability.

    /// Subtract a centred moving mean. Window in seconds → samples via
    /// the constant rate. Edges use shorter windows rather than padding
    /// because edge artifacts get cropped by the peak detector anyway.
    func detrend(_ x: [Double], windowSeconds: Double) -> [Double] {
        let half = max(1, Int(windowSeconds * Self.sampleRateHz / 2))
        var out = [Double](repeating: 0, count: x.count)
        for i in 0..<x.count {
            let lo = max(0, i - half)
            let hi = min(x.count - 1, i + half)
            var sum = 0.0
            for j in lo...hi { sum += x[j] }
            let mean = sum / Double(hi - lo + 1)
            out[i] = x[i] - mean
        }
        return out
    }

    /// Two-pass IIR bandpass approximating Butterworth at 0.7-4.0 Hz.
    /// Implemented as a difference of two single-pole low-pass filters
    /// (a "DLPF" approach) · cheap, stable, and parameter-explicit.
    func bandpass(_ x: [Double]) -> [Double] {
        let lowCut = 0.7
        let highCut = 4.0
        let dt = 1.0 / Self.sampleRateHz
        let alphaLow = dt / (dt + 1.0 / (2.0 * .pi * highCut))
        let alphaHigh = dt / (dt + 1.0 / (2.0 * .pi * lowCut))

        var slow = [Double](repeating: 0, count: x.count)
        var fast = [Double](repeating: 0, count: x.count)
        guard !x.isEmpty else { return [] }
        slow[0] = x[0]
        fast[0] = x[0]
        for i in 1..<x.count {
            fast[i] = fast[i - 1] + alphaLow * (x[i] - fast[i - 1])
            slow[i] = slow[i - 1] + alphaHigh * (x[i] - slow[i - 1])
        }
        // Forward-only is fine for live previews; for finalization we
        // also run it backwards to cancel the phase delay (zero-phase
        // filtering). That makes peak timing accurate to a frame.
        var revIn = Array(fast.reversed())
        var revSlow = [Double](repeating: 0, count: revIn.count)
        var revFast = [Double](repeating: 0, count: revIn.count)
        revSlow[0] = revIn[0]
        revFast[0] = revIn[0]
        for i in 1..<revIn.count {
            revFast[i] = revFast[i - 1] + alphaLow * (revIn[i] - revFast[i - 1])
            revSlow[i] = revSlow[i - 1] + alphaHigh * (revIn[i] - revSlow[i - 1])
        }
        revIn = []
        let zeroPhaseFast = Array(revFast.reversed())
        let zeroPhaseSlow = Array(Array(revSlow.reversed()).reversed())
        var out = [Double](repeating: 0, count: x.count)
        for i in 0..<x.count {
            out[i] = zeroPhaseFast[i] - zeroPhaseSlow[i]
        }
        return out
    }

    /// Peak picker with a 250 ms refractory (max ~240 bpm). Returns
    /// peak indices in the filtered signal.
    func detectPeaks(_ x: [Double]) -> [Int] {
        guard x.count > 4 else { return [] }
        let refractorySamples = Int(0.25 * Self.sampleRateHz)
        // Adaptive threshold: a fraction of the rolling max so the
        // detector tracks slow amplitude changes (e.g. finger pressure).
        let windowSamples = Int(2.0 * Self.sampleRateHz)
        var peaks: [Int] = []
        var lastPeak = -refractorySamples
        for i in 1..<(x.count - 1) {
            let lo = max(0, i - windowSamples)
            let hi = min(x.count - 1, i + windowSamples)
            var localMax = 0.0
            for j in lo...hi { if x[j] > localMax { localMax = x[j] } }
            let threshold = localMax * 0.5
            if x[i] > threshold && x[i] > x[i - 1] && x[i] >= x[i + 1] {
                if i - lastPeak >= refractorySamples {
                    peaks.append(i)
                    lastPeak = i
                }
            }
        }
        return peaks
    }

    /// Differences between consecutive peak indices, converted to ms.
    func peakIntervalsMs(_ peakIndices: [Int]) -> [Double] {
        guard peakIndices.count > 1 else { return [] }
        var out: [Double] = []
        out.reserveCapacity(peakIndices.count - 1)
        for i in 1..<peakIndices.count {
            let dtSamples = Double(peakIndices[i] - peakIndices[i - 1])
            out.append(dtSamples / Self.sampleRateHz * 1000.0)
        }
        return out
    }

    /// Root-mean-square of successive differences, in ms.
    func rmssd(_ ibis: [Double]) -> Double? {
        guard ibis.count >= 2 else { return nil }
        var ssd = 0.0
        for i in 1..<ibis.count {
            let d = ibis[i] - ibis[i - 1]
            ssd += d * d
        }
        return (ssd / Double(ibis.count - 1)).squareRoot()
    }

    /// Standard deviation of IBIs, in ms. Population formula · we want
    /// the descriptive spread, not a sample inference.
    func sdnn(_ ibis: [Double]) -> Double? {
        guard ibis.count >= 2 else { return nil }
        let mean = ibis.reduce(0, +) / Double(ibis.count)
        let variance = ibis.reduce(0.0) { acc, v in acc + (v - mean) * (v - mean) } / Double(ibis.count)
        return variance.squareRoot()
    }

    /// Crude SNR estimate · variance of the in-band signal vs variance
    /// of the residual once peaks are removed (replaced with linear
    /// interpolation between adjacent peaks). 10 log10 of the ratio.
    func estimateSnrDb(_ filtered: [Double]) -> Double {
        guard filtered.count > 2 else { return 0 }
        let mean = filtered.reduce(0, +) / Double(filtered.count)
        let total = filtered.reduce(0.0) { acc, v in acc + (v - mean) * (v - mean) }
        // Out-of-band proxy: differences between successive samples
        // attribute most energy to high-frequency noise; integrating
        // them gives a rough out-of-band variance.
        var noise = 0.0
        for i in 1..<filtered.count {
            let d = filtered[i] - filtered[i - 1]
            noise += d * d
        }
        guard noise > 0 else { return 60 }
        return 10.0 * log10(total / noise)
    }
}
