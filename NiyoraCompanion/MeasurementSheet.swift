import SwiftUI

/// Full-screen sheet shown for the duration of a PPG capture. The
/// visual flow walks the user through placing their finger on the
/// camera, a short ready pause, the 30 s capture itself, and a result
/// screen with both HRV and heart rate.
///
/// The aesthetic matches Niyora's breathing canvas · deep purple
/// gradient, a soft violet particle orb, Poppins-style soft type.
/// During capture the orb's pulse syncs to the user's heart rhythm.
///
/// Used for both Mac-initiated measurements (Measure stress on Mac)
/// and phone-initiated ones (Measure button on the iOS app home).
struct MeasurementSheet: View {
    @Bindable var controller: MeasurementController
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            niyoraBackdrop
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.top, 18)
                Spacer(minLength: 24)
                content
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 24)
                footer
                    .padding(.bottom, 28)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white)

            cancelChip
        }
    }

    /// Same gradient as the Mac's breathing canvas / mood backdrop, so
    /// the sheet feels continuous with the rest of the product.
    private var niyoraBackdrop: some View {
        ZStack {
            Color(red: 0.04, green: 0.035, blue: 0.075)
            // Top glow
            RadialGradient(
                colors: [Color(hue: 0.70, saturation: 0.5, brightness: 0.35, opacity: 0.65), .clear],
                center: UnitPoint(x: 0.5, y: 0.3),
                startRadius: 0,
                endRadius: 340
            )
            // Bottom glow
            RadialGradient(
                colors: [Color(hue: 0.74, saturation: 0.5, brightness: 0.22, opacity: 0.55), .clear],
                center: UnitPoint(x: 0.5, y: 0.92),
                startRadius: 0,
                endRadius: 380
            )
        }
    }

    private var cancelChip: some View {
        Button {
            onCancel()
        } label: {
            Image(systemName: "xmark")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
                .padding(10)
                .background(.white.opacity(0.08), in: Circle())
        }
        .padding(.leading, 18)
        .padding(.top, 12)
        .accessibilityLabel("Cancel measurement")
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(eyebrowText)
                .font(.system(size: 11, weight: .medium))
                .textCase(.uppercase)
                .tracking(3)
                .foregroundStyle(.white.opacity(0.45))
            if !controller.isStandalone, !controller.techniqueName.isEmpty {
                Text(controller.techniqueName)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    private var eyebrowText: String {
        if controller.isStandalone { return "Stress check" }
        return controller.phase == .pre ? "Before breath" : "After breath"
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
        VStack(spacing: 20) {
            NiyoraOrb(size: 140, hue: 0.78, intensity: 0.6, pulseDuration: 5.4)
            Text("Getting the camera ready")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.72))
        }
    }

    private var placingFingerView: some View {
        VStack(spacing: 28) {
            // Live camera preview in a violet-tinted ring. The user
            // sees the room until they cover the lens · once their
            // finger is on it the preview goes dark red, which is
            // the visual cue that they've found the right lens.
            ZStack {
                CameraPreview(session: controller.capture.session)
                    .frame(width: 240, height: 240)
                    .clipShape(Circle())
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(hue: 0.78, saturation: 0.5, brightness: 0.85, opacity: 0.85),
                                Color(hue: 0.78, saturation: 0.4, brightness: 0.55, opacity: 0.55),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 244, height: 244)
                    .shadow(
                        color: Color(hue: 0.78, saturation: 0.6, brightness: 0.5).opacity(0.45),
                        radius: 18, x: 0, y: 0
                    )
                // Overlay tag · only visible while no finger detected.
                if !controller.fingerOnLens {
                    Text("No finger")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.55), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                }
            }

            VStack(spacing: 8) {
                Text("Place your finger on the camera")
                    .font(.system(size: 17, weight: .medium))
                Text("Cover the lens firmly. Hold steady at heart level.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
        }
    }

    private func readyView(remaining: Double) -> some View {
        VStack(spacing: 22) {
            NiyoraOrb(size: 160, hue: 0.78, intensity: 0.85, pulseDuration: 2.6)
            Text("Ready")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white.opacity(0.65))
                .tracking(2)
                .textCase(.uppercase)
            Text("\(Int(remaining.rounded(.up)))")
                .font(.system(size: 88, weight: .light, design: .rounded))
                .monospacedDigit()
            Text("Keep still. Reading starts now.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.65))
        }
        .animation(.easeOut(duration: 0.2), value: Int(remaining.rounded(.up)))
    }

    private func capturingView(elapsed: Double) -> some View {
        let total = MeasurementController.captureDurationSec
        let remaining = max(0, total - elapsed)
        let remainingSec = Int(remaining.rounded(.up))
        let progress = min(1.0, elapsed / total)
        return VStack(spacing: 22) {
            ZStack {
                NiyoraOrb(size: 200, hue: 0.78, intensity: 0.95, pulseDuration: 1.0)
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 3)
                    .frame(width: 220, height: 220)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.white.opacity(0.85),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 220, height: 220)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: progress)
                VStack(spacing: 2) {
                    Text("\(remainingSec)")
                        .font(.system(size: 56, weight: .light, design: .rounded))
                        .monospacedDigit()
                    Text("seconds")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.5))
                        .tracking(2)
                        .textCase(.uppercase)
                }
            }
            VStack(spacing: 6) {
                Text("Reading your pulse")
                    .font(.system(size: 16, weight: .medium))
                Text(controller.fingerOnLens
                    ? "Keep still. Don't lift your finger."
                    : "Press your finger more firmly over the lens.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            if controller.fingerOnLens {
                WaveformView(samples: controller.previewSignal)
                    .frame(height: 60)
                    .padding(.horizontal, 16)
                    .opacity(0.85)
            }
        }
    }

    private func finishedView(_ result: PPGMeasurementResult) -> some View {
        VStack(spacing: 20) {
            switch result.status {
            case .ok:
                NiyoraOrb(size: 120, hue: 0.78, intensity: 0.9, pulseDuration: 5.4)
                resultStat(
                    icon: "waveform.path.ecg",
                    iconTint: Color(hue: 0.78, saturation: 0.5, brightness: 0.95),
                    label: "HRV",
                    value: result.rmssdMs.map { String(format: "%.0f", $0) } ?? "—",
                    unit: "ms"
                )
                resultStat(
                    icon: "heart.fill",
                    iconTint: Color(hue: 0.95, saturation: 0.6, brightness: 0.95),
                    label: "Heart rate",
                    value: controller.heartRateBpm.map { String(format: "%.0f", $0) } ?? "—",
                    unit: "bpm"
                )
                disclaimerCopy
            case .lowSignal:
                resultProblem(
                    icon: "waveform.slash",
                    title: "Reading was too noisy",
                    body: "Cover the camera and flashlight firmly with your fingertip. Keep your phone still at heart level."
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(iconTint)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.75))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(size: 56, weight: .light, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 36)
    }

    private func resultProblem(icon: String, title: String, body: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color(hue: 0.78, saturation: 0.5, brightness: 0.85))
            Text(title)
                .font(.system(size: 19, weight: .medium))
            Text(body)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.horizontal, 28)
        }
    }

    private var disclaimerCopy: some View {
        Text("Informational and wellness only. Not a medical device, not a substitute for medical advice.")
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.42))
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 36)
            .padding(.top, 6)
    }

    private func failedView(_ reason: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.orange)
            Text("Could not start the camera")
                .font(.system(size: 19, weight: .medium))
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
                primaryPill(title: "Done", action: onDone)
            case .lowSignal, .fingerLifted:
                HStack(spacing: 12) {
                    secondaryPill(title: "Close", action: onDone)
                    primaryPill(title: "Try again", action: onRetry)
                }
            }
        case .failed:
            primaryPill(title: "Close", action: onDone)
        default:
            EmptyView()
        }
    }

    private func primaryPill(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .tracking(2)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [
                            Color(hue: 0.78, saturation: 0.55, brightness: 0.45, opacity: 0.85),
                            Color(hue: 0.78, saturation: 0.45, brightness: 0.35, opacity: 0.85),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                .foregroundStyle(.white)
        }
    }

    private func secondaryPill(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .tracking(2)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

/// Niyora-family soft particle orb. Pure SwiftUI, no asset · uses the
/// same radial-gradient + box-shadow approach as the Mac canvas. The
/// hue parameter lets the caller swap between Shine violet (~0.78) and
/// the warmer tier hues if needed in the future.
private struct NiyoraOrb: View {
    let size: CGFloat
    let hue: Double
    let intensity: Double
    let pulseDuration: Double

    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hue: hue, saturation: 0.6, brightness: 0.95, opacity: 0.95 * intensity),
                            Color(hue: hue, saturation: 0.55, brightness: 0.55, opacity: 0.82 * intensity),
                            Color(hue: hue - 0.04, saturation: 0.5, brightness: 0.18, opacity: 0.85 * intensity),
                        ],
                        center: UnitPoint(x: 0.35, y: 0.3),
                        startRadius: 4,
                        endRadius: size * 0.55
                    )
                )
                .frame(width: size, height: size)
                .shadow(
                    color: Color(hue: hue, saturation: 0.6, brightness: 0.55).opacity(0.45 * intensity),
                    radius: size * 0.3,
                    x: 0, y: 0
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        }
        .scaleEffect(pulsing ? 1.04 : 1.0)
        .onAppear {
            withAnimation(.easeInOut(duration: pulseDuration).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}
