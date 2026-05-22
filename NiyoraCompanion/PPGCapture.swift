import AVFoundation
import CoreVideo
import UIKit

/// AVFoundation-based camera capture for PPG.
///
/// Turns on the back camera and the torch, pins the format to 30 fps,
/// and exposes a stream of mean green-channel values from a centred ROI.
/// One instance per measurement; the owning controller calls `start()`
/// at sheet present, `stop()` on dismissal or completion.
///
/// We deliberately keep the ROI small (a 200x200 px square in the centre
/// of the frame, scaled to whatever resolution the device produces).
/// Averaging fewer pixels means each frame's computation is fast and
/// the user has to centre their fingertip on the lens · which produces
/// a cleaner pulse signal than averaging the whole frame.
final class PPGCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    /// Called on the main actor with each new green-channel mean. The
    /// owning controller appends to the signal processor and updates UI.
    typealias FrameHandler = @MainActor (Double) -> Void

    enum StartError: Error {
        case noBackCamera
        case noTorch
        case configurationFailed(String)
    }

    /// The shared capture session · exposed (read-only is enforced by
    /// the actor / single-writer pattern) so the sheet can show a live
    /// preview during the place-finger stage. Same session that drives
    /// the per-frame green-channel sampling.
    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let sampleQueue = DispatchQueue(label: "niyora.ppg.samples")
    private var device: AVCaptureDevice?
    private var onFrame: FrameHandler?

    /// Start a capture. Returns once the session is running with the
    /// torch on, or throws if the camera or torch is unavailable.
    func start(onFrame: @escaping FrameHandler) async throws {
        // Permission. iOS already shows the system sheet on first use
        // via NSCameraUsageDescription · we just await the decision.
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw StartError.configurationFailed("Camera access denied.")
        }

        guard let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw StartError.noBackCamera
        }
        guard dev.hasTorch else {
            throw StartError.noTorch
        }
        self.device = dev
        self.onFrame = onFrame

        session.beginConfiguration()
        session.sessionPreset = .vga640x480

        do {
            let input = try AVCaptureDeviceInput(device: dev)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            session.commitConfiguration()
            throw StartError.configurationFailed(error.localizedDescription)
        }

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        output.setSampleBufferDelegate(self, queue: sampleQueue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()

        // Pin to 30 fps so the signal processor's assumed sampleRateHz
        // matches reality. We deliberately do NOT use continuous auto
        // exposure or auto white balance during the capture · those
        // adjust gain frame-to-frame, which the PPG pipeline reads as
        // noise and the finger-on detector misreads as "no finger."
        // `.autoExpose` triggers a one-shot exposure pass and then
        // locks, which gives a stable baseline for the measurement.
        do {
            try dev.lockForConfiguration()
            let target = CMTime(value: 1, timescale: 30)
            dev.activeVideoMinFrameDuration = target
            dev.activeVideoMaxFrameDuration = target
            if dev.isExposureModeSupported(.autoExpose) {
                dev.exposureMode = .autoExpose
            } else if dev.isExposureModeSupported(.locked) {
                dev.exposureMode = .locked
            }
            if dev.isWhiteBalanceModeSupported(.autoWhiteBalance) {
                dev.whiteBalanceMode = .autoWhiteBalance
            } else if dev.isWhiteBalanceModeSupported(.locked) {
                dev.whiteBalanceMode = .locked
            }
            dev.unlockForConfiguration()
        } catch {
            throw StartError.configurationFailed("Could not configure fps: \(error.localizedDescription)")
        }

        await Task.detached(priority: .userInitiated) { [session] in
            session.startRunning()
        }.value

        // Some devices need a beat between session-running and the
        // torch coming on · the AVCaptureSession is technically
        // running when startRunning returns, but the underlying media
        // pipeline isn't always immediately ready to actually drive
        // the torch on iPhone 14/15/16 with adaptive true-tone flash.
        try? await Task.sleep(nanoseconds: 250_000_000)

        // Torch on. `torchMode = .on` is the older, simpler property
        // and seems to work on devices where setTorchModeOnWithLevel
        // silently fails. We try `.on` first, fall back to the
        // level-based variant only if it fails.
        print("[PPGCapture] pre-torch · hasTorch=\(dev.hasTorch) isTorchAvailable=\(dev.isTorchAvailable) supportsOn=\(dev.isTorchModeSupported(.on)) isTorchActive=\(dev.isTorchActive)")
        do {
            try dev.lockForConfiguration()
            if dev.hasTorch {
                if dev.isTorchModeSupported(.on) {
                    dev.torchMode = .on
                }
                // If that didn't actually turn the LED on, try the
                // explicit-level API as a fallback.
                if !dev.isTorchActive, dev.isTorchAvailable {
                    do {
                        try dev.setTorchModeOn(level: 1.0)
                    } catch {
                        print("[PPGCapture] setTorchModeOn fallback failed: \(error.localizedDescription)")
                    }
                }
            }
            dev.unlockForConfiguration()
            print("[PPGCapture] post-torch · torchMode=\(dev.torchMode.rawValue) isTorchActive=\(dev.isTorchActive) torchLevel=\(dev.torchLevel)")
        } catch {
            print("[PPGCapture] lockForConfiguration failed: \(error.localizedDescription)")
        }
    }

    /// Stop the session and turn the torch off. Idempotent.
    func stop() {
        if session.isRunning { session.stopRunning() }
        if let dev = device {
            try? dev.lockForConfiguration()
            if dev.torchMode == .on { dev.torchMode = .off }
            dev.unlockForConfiguration()
        }
        onFrame = nil
        device = nil
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let green = Self.meanGreenInCenterROI(pixelBuffer)
        guard let handler = onFrame else { return }
        Task { @MainActor in
            handler(green)
        }
    }

    /// Average the green byte across a 200x200 centred ROI. Returns 0
    /// if locking the pixel buffer fails · the signal processor's
    /// finger-detector will mark that as "no finger" rather than a peak.
    static func meanGreenInCenterROI(_ pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let roiW = min(200, width)
        let roiH = min(200, height)
        let startX = (width - roiW) / 2
        let startY = (height - roiH) / 2

        let buffer = base.assumingMemoryBound(to: UInt8.self)
        var sum: UInt64 = 0
        var count: UInt64 = 0
        for y in startY..<(startY + roiH) {
            let row = buffer.advanced(by: y * bytesPerRow)
            for x in startX..<(startX + roiW) {
                // BGRA layout · green is byte index 1 in each pixel.
                sum &+= UInt64(row[x * 4 + 1])
                count &+= 1
            }
        }
        guard count > 0 else { return 0 }
        return Double(sum) / Double(count)
    }
}
