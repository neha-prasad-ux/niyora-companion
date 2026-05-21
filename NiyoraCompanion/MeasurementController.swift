import Foundation
import UIKit

/// Drives one 30s PPG capture from start to result. Owned by the
/// presenting view; the view subscribes to `state` (Observation) to
/// render the sheet's live waveform, countdown, and final outcome.
///
/// Lifecycle:
///
///   sheet appears → start()
///       → state = .preparing                 (camera coming up)
///       → state = .capturing(elapsed: 0..30) (per-frame updates)
///       → state = .finished(result)          OR .failed(reason)
///   sheet dismissed → cancel()
@MainActor
@Observable
final class MeasurementController {

    enum State: Equatable {
        case idle
        case preparing
        case capturing(elapsed: Double)
        case finished(PPGMeasurementResult)
        case failed(String)
    }

    /// How long a measurement lasts, in seconds. Locked at 30s per the
    /// spec · 30s gives enough IBIs for RMSSD without making the user
    /// hold their finger uncomfortably long.
    static let captureDurationSec: Double = 30.0
    /// We discard the first second or so of samples so the AGC + torch
    /// settle. The signal processor still sees a 29s window for the
    /// final compute · plenty for RMSSD.
    private static let warmupDurationSec: Double = 1.5

    let sessionId: String
    let phase: MeasurementPhase
    let techniqueName: String

    private(set) var state: State = .idle
    /// Latest filtered signal slice for the waveform preview. Most-recent
    /// ~5s of bandpassed samples, downsampled to ~60 points for the SVG.
    private(set) var previewSignal: [Double] = []
    /// Whether the latest 0.5s of samples looks like a finger is on the
    /// lens. UI uses this to render the "finger on lens" hint.
    private(set) var fingerOnLens: Bool = false

    private let capture = PPGCapture()
    private var processor = PPGSignalProcessor()
    private var startedAt: Date?
    private var tickTask: Task<Void, Never>?
    /// Counts contiguous frames where the finger-on detector says
    /// "no finger". If this stays high for over a second mid-capture
    /// we abort with `.fingerLifted` rather than producing junk metrics.
    private var noFingerStreakFrames = 0

    init(sessionId: String, phase: MeasurementPhase, techniqueName: String) {
        self.sessionId = sessionId
        self.phase = phase
        self.techniqueName = techniqueName
    }

    /// Begin the capture. Idempotent · a second call while running is a
    /// no-op. Errors during camera setup transition to `.failed`.
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
        startedAt = Date()
        state = .capturing(elapsed: 0)
        // Keep the screen awake while the user is asked to hold still.
        UIApplication.shared.isIdleTimerDisabled = true
        scheduleTick()
    }

    /// Cancel an in-progress capture (sheet dismissed). Sends a
    /// `cancelled`-status result back via the completion callback so
    /// the Mac can prune the queued request.
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

    // MARK: - Frame ingestion

    private nonisolated func onFrame(greenMean: Double) {
        // The capture callback already hops to the main actor before
        // calling us; this nonisolated wrapper is just the closure
        // signature seen by AVFoundation.
        Task { @MainActor [weak self] in
            self?.appendFrame(greenMean: greenMean)
        }
    }

    private func appendFrame(greenMean: Double) {
        guard case .capturing = state else { return }
        processor.append(greenMean)
        fingerOnLens = processor.fingerLikelyOnLens()
        if fingerOnLens {
            noFingerStreakFrames = 0
        } else {
            noFingerStreakFrames += 1
        }
        // 30 fps · 1s contiguous = 30 frames. Allow a few before aborting
        // so a brief jitter doesn't kill the capture.
        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        if elapsed > Self.warmupDurationSec, noFingerStreakFrames > Int(PPGSignalProcessor.sampleRateHz * 1.5) {
            finalize(captureCompleted: false)
            return
        }
        refreshPreview()
    }

    /// Build the waveform preview from the most recent ~5s of samples.
    /// Cheap · we bandpass only the tail and downsample to ~60 points.
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
        // Downsample to ~60 points so the SwiftUI Canvas renders smoothly.
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

    // MARK: - Tick + finalize

    private func scheduleTick() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self else { return }
                guard let started = self.startedAt else { return }
                let elapsed = Date().timeIntervalSince(started)
                if case .capturing = self.state {
                    self.state = .capturing(elapsed: min(elapsed, Self.captureDurationSec))
                }
                if elapsed >= Self.captureDurationSec {
                    self.finalize(captureCompleted: true)
                    return
                }
            }
        }
    }

    private func finalize(captureCompleted: Bool) {
        tickTask?.cancel()
        tickTask = nil
        capture.stop()
        UIApplication.shared.isIdleTimerDisabled = false

        // Drop the warmup samples before compute. The signal processor's
        // own `dropFirst` mutates the buffer, but we want the live
        // preview unaltered during the capture · so we apply the drop
        // on a copy.
        var finalProcessor = processor
        let warmupSamples = Int(Self.warmupDurationSec * PPGSignalProcessor.sampleRateHz)
        finalProcessor.dropFirst(warmupSamples)
        let result = finalProcessor.computeResult(captureCompleted: captureCompleted)
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
