import Foundation
import UIKit

/// Drives one 30s PPG capture from start to result. Owned by the
/// presenting view; the view subscribes to `state` (Observation) to
/// render the sheet's live waveform, countdown, and final outcome.
///
/// Lifecycle:
///
///   sheet appears → start()
///       → state = .preparing                   (camera coming up)
///       → state = .placingFinger               (camera ready, waiting on user)
///       → state = .readyCountdown(remaining)   (finger on, 2s settling pause)
///       → state = .capturing(elapsed: 0..30)   (per-frame updates)
///       → state = .finished(result)            OR .failed(reason)
///   sheet dismissed → cancel()
@MainActor
@Observable
final class MeasurementController {

    enum State: Equatable {
        case idle
        case preparing
        case placingFinger
        case readyCountdown(remaining: Double)
        case capturing(elapsed: Double)
        case finished(PPGMeasurementResult)
        case failed(String)
    }

    /// How long a capture lasts, in seconds. Locked at 30s per the spec.
    static let captureDurationSec: Double = 30.0
    /// First seconds of the capture we discard so AGC + torch settle.
    private static let warmupDurationSec: Double = 1.5
    /// Pause between "finger placed" and "capture starts" so the user
    /// can settle in. Short, so it doesn't feel like a delay.
    private static let readyCountdownSec: Double = 2.0

    let sessionId: String
    let phase: MeasurementPhase
    let techniqueName: String
    /// True when the phone initiated the measurement itself (no Mac
    /// request frame in flight). The result still flows to the Mac on
    /// the same wire if paired, but the UI shouldn't say "after breath."
    let isStandalone: Bool

    private(set) var state: State = .idle
    private(set) var previewSignal: [Double] = []
    private(set) var fingerOnLens: Bool = false
    /// Computed beats-per-minute over the last few seconds of capture,
    /// for the result screen. Nil until the result is finalized.
    private(set) var heartRateBpm: Double? = nil

    private let capture = PPGCapture()
    private var processor = PPGSignalProcessor()
    private var captureStartedAt: Date?
    private var tickTask: Task<Void, Never>?
    private var noFingerStreakFrames = 0
    private let haptics = UIImpactFeedbackGenerator(style: .medium)
    private let successHaptic = UINotificationFeedbackGenerator()

    init(
        sessionId: String,
        phase: MeasurementPhase,
        techniqueName: String,
        isStandalone: Bool = false
    ) {
        self.sessionId = sessionId
        self.phase = phase
        self.techniqueName = techniqueName
        self.isStandalone = isStandalone
    }

    func start() async {
        guard case .idle = state else { return }
        state = .preparing
        do {
            try await capture.start { [weak self] green in
                self?.onFrame(greenMean: green)
            }
        } catch {
            state = .failed(friendlyStartError(error))
            return
        }
        state = .placingFinger
        UIApplication.shared.isIdleTimerDisabled = true
        haptics.prepare()
        successHaptic.prepare()
        scheduleTick()
    }

    func cancel() {
        tickTask?.cancel()
        tickTask = nil
        capture.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        if case .finished = state { return }
        if case .failed = state { return }
        state = .finished(PPGMeasurementResult(
            rmssdMs: nil, sdnnMs: nil,
            sampleCount: 0, snrDb: nil,
            status: .cancelled
        ))
    }

    private nonisolated func onFrame(greenMean: Double) {
        Task { @MainActor [weak self] in
            self?.appendFrame(greenMean: greenMean)
        }
    }

    private func appendFrame(greenMean: Double) {
        switch state {
        case .placingFinger, .readyCountdown, .capturing:
            processor.append(greenMean)
        default:
            return
        }
        fingerOnLens = processor.fingerLikelyOnLens()

        switch state {
        case .placingFinger:
            // Transition to readyCountdown when a finger is detected.
            if fingerOnLens {
                haptics.impactOccurred()
                state = .readyCountdown(remaining: Self.readyCountdownSec)
            }
        case .readyCountdown(let remaining):
            // If finger lifts during the ready pause, go back.
            if !fingerOnLens {
                state = .placingFinger
                return
            }
            // Countdown decrements via the tick task. Don't recompute
            // here; just track the streak.
            _ = remaining
        case .capturing:
            if fingerOnLens {
                noFingerStreakFrames = 0
            } else {
                noFingerStreakFrames += 1
            }
            let elapsed = captureStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            if elapsed > Self.warmupDurationSec,
               noFingerStreakFrames > Int(PPGSignalProcessor.sampleRateHz * 1.5) {
                finalize(captureCompleted: false)
                return
            }
            refreshPreview()
        default:
            break
        }
    }

    private func refreshPreview() {
        let tailSec = 5.0
        let tailCount = Int(tailSec * PPGSignalProcessor.sampleRateHz)
        guard processor.samples.count > tailCount else {
            previewSignal = []
            return
        }
        let tail = Array(processor.samples.suffix(tailCount))
        let detrended = processor.detrend(tail, windowSeconds: 1.0)
        let bandpassed = processor.bandpass(detrended)
        let target = 60
        if bandpassed.count <= target {
            previewSignal = bandpassed
        } else {
            let step = bandpassed.count / target
            var out: [Double] = []
            out.reserveCapacity(target)
            for i in 0..<target {
                out.append(bandpassed[i * step])
            }
            previewSignal = out
        }
    }

    private func scheduleTick() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self else { return }
                self.tickOnce()
                if case .finished = self.state { return }
                if case .failed = self.state { return }
            }
        }
    }

    private func tickOnce() {
        switch state {
        case .readyCountdown(let remaining):
            let next = remaining - 0.1
            if next <= 0 {
                state = .capturing(elapsed: 0)
                captureStartedAt = Date()
                haptics.impactOccurred()
            } else {
                state = .readyCountdown(remaining: next)
            }
        case .capturing:
            guard let started = captureStartedAt else { return }
            let elapsed = Date().timeIntervalSince(started)
            state = .capturing(elapsed: min(elapsed, Self.captureDurationSec))
            if elapsed >= Self.captureDurationSec {
                finalize(captureCompleted: true)
            }
        default:
            break
        }
    }

    private func finalize(captureCompleted: Bool) {
        tickTask?.cancel()
        tickTask = nil
        capture.stop()
        UIApplication.shared.isIdleTimerDisabled = false

        var finalProcessor = processor
        let warmupSamples = Int(Self.warmupDurationSec * PPGSignalProcessor.sampleRateHz)
        finalProcessor.dropFirst(warmupSamples)
        let result = finalProcessor.computeResult(captureCompleted: captureCompleted)
        // Heart rate from the same IBI list · convenience for the
        // result screen, not sent to the Mac in v1.
        if result.status == .ok {
            let bandpassed = finalProcessor.bandpass(
                finalProcessor.detrend(finalProcessor.samples, windowSeconds: 1.5)
            )
            let peaks = finalProcessor.detectPeaks(bandpassed)
            let ibis = finalProcessor.peakIntervalsMs(peaks)
            if !ibis.isEmpty {
                let meanMs = ibis.reduce(0, +) / Double(ibis.count)
                heartRateBpm = 60_000.0 / meanMs
            }
            successHaptic.notificationOccurred(.success)
        } else if result.status == .lowSignal || result.status == .fingerLifted {
            successHaptic.notificationOccurred(.warning)
        }
        state = .finished(result)
    }

    private func friendlyStartError(_ error: Error) -> String {
        if let e = error as? PPGCapture.StartError {
            switch e {
            case .noBackCamera:
                return "This iPhone doesn't have a back camera available."
            case .noTorch:
                return "This iPhone doesn't have a torch · PPG needs the flashlight."
            case .configurationFailed(let why):
                return why
            }
        }
        return error.localizedDescription
    }
}
