import SwiftUI

/// Full-screen sheet shown for the duration of a PPG capture. Renders:
///
/// - A countdown ring around a finger glyph.
/// - The live waveform once the signal stabilises.
/// - A "place finger on the camera lens" prompt while the detector
///   doesn't see one.
/// - The final result (or honest "low signal, try again") at the end.
///
/// The owning view (ContentView) holds the controller and dismisses the
/// sheet either when the user taps Cancel or once the result has been
/// sent to the Mac.
struct MeasurementSheet: View {
    @Bindable var controller: MeasurementController
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 24) {
                header
                Spacer(minLength: 0)
                content
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .foregroundStyle(.white)
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(controller.phase == .pre ? "Before breath" : "After breath")
                .font(.caption.weight(.medium))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.6))
            if !controller.techniqueName.isEmpty {
                Text(controller.techniqueName)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .idle, .preparing:
            preparingView
        case .capturing(let elapsed):
            capturingView(elapsed: elapsed)
        case .finished(let result):
            finishedView(result)
        case .failed(let reason):
            failedView(reason)
        }
    }

    private var preparingView: some View {
        VStack(spacing: 18) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
            Text("Getting the camera ready")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.75))
        }
    }

    private func capturingView(elapsed: Double) -> some View {
        let total = MeasurementController.captureDurationSec
        let progress = min(elapsed / total, 1.0)
        let remaining = Int((total - elapsed).rounded(.up))
        return VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: progress)
                VStack(spacing: 4) {
                    Text("\(max(remaining, 0))")
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .monospacedDigit()
                    Text("seconds")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(width: 160, height: 160)

            if controller.fingerOnLens {
                WaveformView(samples: controller.previewSignal)
                    .frame(height: 60)
                    .padding(.horizontal, 16)
            } else {
                Text("Place your fingertip over the back camera and flashlight.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 24)
            }
        }
    }

    private func finishedView(_ result: PPGMeasurementResult) -> some View {
        VStack(spacing: 14) {
            switch result.status {
            case .ok:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.green)
                Text("Estimate sent")
                    .font(.title3.weight(.semibold))
                if let rmssd = result.rmssdMs {
                    Text(String(format: "RMSSD ~%.0f ms", rmssd))
                        .font(.footnote.monospaced())
                        .foregroundStyle(.white.opacity(0.65))
                }
                Text("Single readings are noisy. Trends matter more than any one number.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 24)
            case .lowSignal:
                Image(systemName: "waveform.slash")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.orange)
                Text("Signal was too noisy")
                    .font(.title3.weight(.semibold))
                Text("Press your fingertip lightly over the lens and try again.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 24)
            case .fingerLifted:
                Image(systemName: "hand.raised.slash")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.orange)
                Text("Finger came off the lens")
                    .font(.title3.weight(.semibold))
            case .cancelled:
                EmptyView()
            }
        }
    }

    private func failedView(_ reason: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.orange)
            Text("Could not start the camera")
                .font(.title3.weight(.semibold))
            Text(reason)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch controller.state {
        case .finished(let result):
            switch result.status {
            case .ok, .cancelled:
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            case .lowSignal, .fingerLifted:
                HStack(spacing: 12) {
                    Button("Close", action: onDone)
                        .buttonStyle(.bordered)
                        .tint(.white)
                    Button("Try again", action: onRetry)
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            }
        case .failed:
            Button("Close", action: onDone)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        default:
            Button("Cancel", role: .destructive, action: onCancel)
                .buttonStyle(.bordered)
                .tint(.white)
                .controlSize(.large)
        }
    }
}
