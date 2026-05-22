import SwiftUI

/// Full-screen sheet shown for the duration of a PPG capture. The
/// visual flow walks the user through placing their finger on the
/// camera, a short ready pause, the 30 s capture itself, and an
/// honest result screen with both HRV and heart rate.
///
/// Used for both Mac-initiated measurements (Measure stress on Mac)
/// and phone-initiated ones (Measure button on the iOS app home).
/// `controller.isStandalone` toggles a couple of copy details so the
/// sheet reads correctly in either context.
struct MeasurementSheet: View {
    @Bindable var controller: MeasurementController
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            backgroundForState()
                .ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer(minLength: 12)
                header
                Spacer(minLength: 0)
                content
                Spacer(minLength: 0)
                footer
                Spacer(minLength: 12)
            }
            .padding(.horizontal, 24)
            .foregroundStyle(.white)
            cancelChip
        }
    }

    // MARK: - Background

    @ViewBuilder
    private func backgroundForState() -> some View {
        switch controller.state {
        case .capturing:
            // Soft red tint during capture so the user feels the
            // pulse · matches the reference apps' visceral cue.
            LinearGradient(
                colors: [Color(red: 0.9, green: 0.1, blue: 0.1).opacity(0.55), .black],
                startPoint: .top,
                endPoint: .bottom
            )
        default:
            Color.black.opacity(0.96)
        }
    }

    private var cancelChip: some View {
        Button {
            onCancel()
        } label: {
            Image(systemName: "xmark")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(10)
                .background(.black.opacity(0.45), in: Circle())
        }
        .padding(.leading, 16)
        .padding(.top, 12)
        .accessibilityLabel("Cancel measurement")
    }

    private var header: some View {
        VStack(spacing: 4) {
            if !controller.isStandalone {
                Text(controller.phase == .pre ? "Before breath" : "After breath")
                    .font(.caption.weight(.medium))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.6))
                if !controller.techniqueName.isEmpty {
                    Text(controller.techniqueName)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))
                }
            } else {
                Text("Stress check")
                    .font(.caption.weight(.medium))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    // MARK: - Content per state

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .idle, .preparing:
            preparingView
        case .placingFinger:
            placingFingerView
        case .readyCountdown(let remaining):
            readyView(remaining: remaining)
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
            ProgressView().progressViewStyle(.circular).tint(.white)
            Text("Getting the camera ready")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var placingFingerView: some View {
        VStack(spacing: 28) {
            HStack(spacing: 16) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
                Text("\(Int(MeasurementController.captureDurationSec))s")
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("s")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .offset(y: 12)
            }
            Text("Place your fingertip over the back camera and flashlight to start.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 16)
            fingerOnCameraGlyph
                .padding(.top, 12)
        }
    }

    /// Stylised illustration of a phone's back camera array with an
    /// arrow pointing at the lens the user should cover. Self-contained
    /// SwiftUI primitives, no asset needed.
    private var fingerOnCameraGlyph: some View {
        ZStack(alignment: .leading) {
            // Phone body outline
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(Color.white.opacity(0.42), lineWidth: 1.5)
                .frame(width: 170, height: 220)
                .padding(.leading, 70)
            // Camera island
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                .frame(width: 90, height: 90)
                .offset(x: 100, y: -50)
            // The target lens (highlighted)
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .background(Circle().fill(Color.white.opacity(0.85)))
                .frame(width: 30, height: 30)
                .offset(x: 124, y: -78)
            // Arrow pointing at the target lens
            Image(systemName: "arrow.right")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .offset(x: 84, y: -78)
        }
        .frame(height: 240)
    }

    private func readyView(remaining: Double) -> some View {
        VStack(spacing: 20) {
            Text("Ready")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.65))
            Text("\(Int(remaining.rounded(.up)))")
                .font(.system(size: 96, weight: .light, design: .rounded))
                .monospacedDigit()
                .transition(.scale)
            Text("Keep still. Reading starts now.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))
        }
        .animation(.easeOut(duration: 0.2), value: Int(remaining.rounded(.up)))
    }

    private func capturingView(elapsed: Double) -> some View {
        let total = MeasurementController.captureDurationSec
        let remaining = max(0, total - elapsed)
        let remainingSec = Int(remaining.rounded(.up))
        return VStack(spacing: 24) {
            HStack(spacing: 14) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, options: .repeating)
                Text("\(remainingSec)")
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("s")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .offset(y: 12)
            }
            Text("Keep still. Reading your pulse.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.82))
            if controller.fingerOnLens {
                WaveformView(samples: controller.previewSignal)
                    .frame(height: 72)
                    .padding(.horizontal, 24)
            } else {
                Text("Press your finger more firmly over the lens.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func finishedView(_ result: PPGMeasurementResult) -> some View {
        VStack(spacing: 18) {
            switch result.status {
            case .ok:
                resultStat(
                    icon: "waveform.path.ecg",
                    iconTint: .pink,
                    label: "HRV",
                    value: result.rmssdMs.map { String(format: "%.0f", $0) } ?? "—",
                    unit: "ms"
                )
                Divider().background(.white.opacity(0.2)).padding(.horizontal, 40)
                resultStat(
                    icon: "heart.fill",
                    iconTint: .red,
                    label: "Heart rate",
                    value: controller.heartRateBpm.map { String(format: "%.0f", $0) } ?? "—",
                    unit: "bpm"
                )
                disclaimerCopy
            case .lowSignal:
                resultProblem(
                    icon: "waveform.slash",
                    title: "Reading was too noisy",
                    body: "Press your fingertip lightly over the lens. Hold steady at heart level."
                )
            case .fingerLifted:
                resultProblem(
                    icon: "hand.raised.slash",
                    title: "Finger came off the lens",
                    body: "Keep your fingertip on the back camera for the whole 30 seconds."
                )
            case .cancelled:
                EmptyView()
            }
        }
    }

    private func resultStat(
        icon: String,
        iconTint: Color,
        label: String,
        value: String,
        unit: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .foregroundStyle(iconTint)
                        .font(.callout)
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.45), in: Capsule())
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(value)
                        .font(.system(size: 56, weight: .bold))
                        .monospacedDigit()
                    Text(unit)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 36)
    }

    private func resultProblem(icon: String, title: String, body: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.orange)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(body)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 24)
        }
    }

    private var disclaimerCopy: some View {
        Text("This data is for informational and wellness purposes only. It is not a medical device and is not a substitute for professional medical advice.")
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 36)
            .padding(.top, 4)
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
                Button(action: onDone) {
                    Text("Done")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.12), in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 8)
            case .lowSignal, .fingerLifted:
                HStack(spacing: 12) {
                    Button("Close", action: onDone)
                        .buttonStyle(.bordered)
                        .tint(.white)
                    Button("Try again", action: onRetry)
                        .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
                .padding(.bottom, 8)
            }
        case .failed:
            Button(action: onDone) {
                Text("Close")
                    .font(.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white.opacity(0.12), in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 8)
        default:
            EmptyView()
        }
    }
}
