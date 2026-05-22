import AVFoundation
import SwiftUI
import UIKit

/// Live preview of an `AVCaptureSession`, suitable for embedding in a
/// SwiftUI view. Used during the place-finger stage of the measurement
/// sheet so the user can see what the camera sees and knows exactly
/// which lens to cover. Once the finger is on the lens, the preview
/// goes mostly red · which doubles as visual confirmation that the
/// finger is in the right place.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
    }

    /// UIKit-backed view whose backing CALayer is the preview layer.
    /// Avoids the awkward sub-layer sizing dance that `addSublayer`
    /// requires inside a SwiftUI view.
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            // Force-cast is safe because layerClass returns the right type.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
