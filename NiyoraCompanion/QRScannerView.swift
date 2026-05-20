import AVFoundation
import SwiftUI

/// Thin SwiftUI wrapper around AVFoundation's metadata QR scanner.
/// Calls `onCode` exactly once per detected QR string and then stops the
/// session ‑ the caller is expected to dismiss the scanner view.
struct QRScannerView: UIViewControllerRepresentable {

    enum Status {
        case ready
        case denied
        case unsupported
    }

    let onCode: (String) -> Void
    let onStatusChange: (Status) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController()
        vc.coordinator = context.coordinator
        vc.onStatusChange = onStatusChange
        return vc
    }

    func updateUIViewController(_ vc: ScannerViewController, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let onCode: (String) -> Void
        private var hasFired = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !hasFired else { return }
            for obj in metadataObjects {
                if let qr = obj as? AVMetadataMachineReadableCodeObject,
                   qr.type == .qr,
                   let value = qr.stringValue {
                    hasFired = true
                    onCode(value)
                    return
                }
            }
        }
    }
}

/// UIViewController hosting the capture preview. Lives outside the
/// SwiftUI representable so we can manage the AVCaptureSession lifecycle
/// across willAppear / willDisappear.
final class ScannerViewController: UIViewController {
    weak var coordinator: QRScannerView.Coordinator?
    var onStatusChange: ((QRScannerView.Status) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureSession() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                guard granted else {
                    self.onStatusChange?(.denied)
                    return
                }
                self.installCaptureGraph()
            }
        }
    }

    private func installCaptureGraph() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            onStatusChange?(.unsupported)
            return
        }
        guard session.canAddInput(input) else {
            onStatusChange?(.unsupported)
            return
        }
        session.addInput(input)

        let metadataOutput = AVCaptureMetadataOutput()
        guard session.canAddOutput(metadataOutput) else {
            onStatusChange?(.unsupported)
            return
        }
        session.addOutput(metadataOutput)
        metadataOutput.setMetadataObjectsDelegate(coordinator, queue: .main)
        metadataOutput.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        previewLayer = preview

        onStatusChange?(.ready)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }
}
