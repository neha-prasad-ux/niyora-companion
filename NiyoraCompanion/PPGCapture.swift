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

    /// Called on the main actor with each new frame's color summary.
    /// Green is the PPG signal channel (hemoglobin absorbs green); red
    /// is carried alongside so the finger-on detector can use the
    /// R/G ratio as a robust "is a finger on the torch" signal.
    typealias FrameHandler = @MainActor (_ green: Double, _ red: Double) -> Void

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
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        // Watch for system-level interruptions of the capture stream.
        // FigXPC err=-17281 floods on user devices were the symptom of
        // these notifications firing while we were oblivious · this
        // surface lets us see the real reason (thermal pressure,
        // another foreground app, hardware contention) instead of
        // guessing from the FigXPC noise.
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: .main
        ) { note in
            #if DEBUG
            let rawReason = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int ?? -1
            print("[PPGCapture] session WAS INTERRUPTED · reason=\(rawReason) (\(Self.interruptionReasonName(rawReason)))")
            #endif
        })
        observers.append(nc.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: .main
        ) { _ in
            #if DEBUG
            print("[PPGCapture] session interruption ENDED")
            #endif
        })
        observers.append(nc.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: .main
        ) { note in
            #if DEBUG
            let err = note.userInfo?[AVCaptureSessionErrorKey]
            print("[PPGCapture] session RUNTIME ERROR · \(String(describing: err))")
            #endif
        })
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }

    #if DEBUG
    private static func interruptionReasonName(_ raw: Int) -> String {
        switch raw {
        case 1: return "videoDeviceNotAvailableInBackground"
        case 2: return "audioDeviceInUseByAnotherClient"
        case 3: return "videoDeviceInUseByAnotherClient"
        case 4: return "videoDeviceNotAvailableWithMultipleForegroundApps"
        case 5: return "videoDeviceNotAvailableDueToSystemPressure"
        default: return "unknown"
        }
    }
    #endif

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
        // matches reality. We leave exposure and white balance at
        // their iOS defaults · the R/G ratio detector is immune to
        // gain changes (both channels move together), and explicitly
        // setting auto-expose modes was destabilising the torch on
        // user's device.
        do {
            try dev.lockForConfiguration()
            let target = CMTime(value: 1, timescale: 30)
            dev.activeVideoMinFrameDuration = target
            dev.activeVideoMaxFrameDuration = target
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
        // silently fails. We try the level variant first, fall back
        // to `.on` only if it throws.
        #if DEBUG
        print("[PPGCapture] pre-torch · hasTorch=\(dev.hasTorch) isTorchAvailable=\(dev.isTorchAvailable) supportsOn=\(dev.isTorchModeSupported(.on)) isTorchActive=\(dev.isTorchActive)")
        #endif
        do {
            try dev.lockForConfiguration()
            if dev.hasTorch, dev.isTorchAvailable {
                // 0.5 keeps the LED bright enough to illuminate the
                // finger without saturating the camera sensor through
                // the skin. Full brightness pushed the green channel
                // above 220 on some skin types, which the finger-on
                // detector then incorrectly rejected.
                do {
                    try dev.setTorchModeOn(level: 0.5)
                } catch {
                    // Fall back to the simpler API, which uses max level.
                    if dev.isTorchModeSupported(.on) {
                        dev.torchMode = .on
                    }
                }
            }
            dev.unlockForConfiguration()
            #if DEBUG
            print("[PPGCapture] post-torch · torchMode=\(dev.torchMode.rawValue) isTorchActive=\(dev.isTorchActive) torchLevel=\(dev.torchLevel)")
            #endif
        } catch {
            throw StartError.configurationFailed("Could not turn on the torch: \(error.localizedDescription)")
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
        let (green, red) = Self.meanGreenRedInCenterROI(pixelBuffer)
        guard let handler = onFrame else { return }
        Task { @MainActor in
            handler(green, red)
        }
    }

    /// Average the green and red bytes across a 200x200 centred ROI.
    /// Returns (0, 0) if locking the pixel buffer fails · the signal
    /// processor's finger-detector will mark that as "no finger."
    static func meanGreenRedInCenterROI(_ pixelBuffer: CVPixelBuffer) -> (green: Double, red: Double) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return (0, 0) }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let roiW = min(200, width)
        let roiH = min(200, height)
        let startX = (width - roiW) / 2
        let startY = (height - roiH) / 2

        let buffer = base.assumingMemoryBound(to: UInt8.self)
        var sumG: UInt64 = 0
        var sumR: UInt64 = 0
        var count: UInt64 = 0
        for y in startY..<(startY + roiH) {
            let row = buffer.advanced(by: y * bytesPerRow)
            for x in startX..<(startX + roiW) {
                // BGRA layout · blue=0, green=1, red=2, alpha=3.
                sumG &+= UInt64(row[x * 4 + 1])
                sumR &+= UInt64(row[x * 4 + 2])
                count &+= 1
            }
        }
        guard count > 0 else { return (0, 0) }
        return (Double(sumG) / Double(count), Double(sumR) / Double(count))
    }
}
