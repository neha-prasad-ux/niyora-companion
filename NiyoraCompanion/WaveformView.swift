#if NIYORA_V1_PPG_ENABLED
import SwiftUI

/// Live pulse waveform shown on the measurement sheet. Renders a
/// downsampled slice of the bandpassed PPG signal as a smooth path.
struct WaveformView: View {
    let samples: [Double]

    var body: some View {
        Canvas { ctx, size in
            guard samples.count > 1 else { return }
            let minV = samples.min() ?? 0
            let maxV = samples.max() ?? 1
            let span = max(maxV - minV, 0.0001)
            let dx = size.width / CGFloat(samples.count - 1)
            var path = Path()
            for i in 0..<samples.count {
                let x = CGFloat(i) * dx
                // Centre vertically · positive deflection points up.
                let normalised = (samples[i] - minV) / span
                let y = size.height * (1.0 - normalised) * 0.9 + size.height * 0.05
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(
                path,
                with: .color(.accentColor.opacity(0.85)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
    }
}
#endif
