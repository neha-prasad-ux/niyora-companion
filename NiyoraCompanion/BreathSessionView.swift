import SwiftUI
import AVFoundation

/// Full breath session flow: pre-session info → animated session →
/// post-session mood capture. Persists the completed session via
/// LocalSessionStore on completion.
struct BreathSessionView: View {
    let technique: Technique
    let onDismiss: () -> Void

    @State private var phase: Phase = .pre
    @State private var muted = false

    enum Phase { case pre, session, post }

    var body: some View {
        ZStack {
            sessionBackgroundGradient.ignoresSafeArea()

            switch phase {
            case .pre:
                PreSessionView(
                    technique: technique,
                    muted: $muted,
                    onBegin: { phase = .session },
                    onCancel: onDismiss
                )
            case .session:
                AnimatedSessionView(
                    technique: technique,
                    muted: muted,
                    onComplete: { phase = .post }
                )
            case .post:
                PostSessionView(
                    technique: technique,
                    onDone: { mood in
                        saveSession(mood: mood)
                        onDismiss()
                    }
                )
            }
        }
        .preferredColorScheme(.dark)
    }

    private func saveSession(mood: Int?) {
        let session = LocalSessionStore.Session(
            id: UUID().uuidString,
            techniqueName: technique.name,
            duration: technique.duration,
            completed: true,
            timestamp: Date(),
            mood: mood
        )
        LocalSessionStore.add(session: session)
    }
}

// Matches BreathHomeView.backgroundGradient exactly so every screen
// in the session flow shares the same indigo backdrop.
private let sessionBackgroundGradient = LinearGradient(
    colors: [
        Color(hue: 280.0 / 360.0, saturation: 0.25, brightness: 0.05),
        Color(hue: 270.0 / 360.0, saturation: 0.20, brightness: 0.02),
        Color.black,
    ],
    startPoint: .top,
    endPoint: .bottom
)

// MARK: - Pre-session info screen

private struct PreSessionView: View {
    let technique: Technique
    @Binding var muted: Bool
    let onBegin: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 8)

            Spacer(minLength: 8)
            orbView
            Spacer(minLength: 8)

            VStack(spacing: 6) {
                Text(technique.name)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(technique.subtitle)
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer(minLength: 24)

            VStack(spacing: 12) {
                beginButton
                    .padding(.horizontal, 24)

                Button("Back") { onCancel() }
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
                    .buttonStyle(.plain)
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 0) {
            Image(systemName: "person")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 44, height: 44)

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .strokeBorder(Color.white.opacity(0.7), lineWidth: 1.2)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 4, height: 4)
                    )
                Text("Niyora")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()

            Button {
                muted.toggle()
            } label: {
                Image(systemName: muted ? "speaker.slash" : "speaker.wave.2")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Pearl-rose orb (same gradient as BreathHomeView.orbView)

    private var orbView: some View {
        let core: CGFloat = 240
        let halo: CGFloat = core * 1.05
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hue: 350.0 / 360.0, saturation: 0.35, brightness: 0.85).opacity(0.30),
                            Color(hue: 350.0 / 360.0, saturation: 0.20, brightness: 0.40).opacity(0.0),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: halo * 0.55
                    )
                )
                .frame(width: halo, height: halo)
                .blur(radius: 6)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.00, green: 0.96, blue: 0.96),
                            Color(red: 0.95, green: 0.80, blue: 0.83),
                            Color(red: 0.55, green: 0.34, blue: 0.42),
                        ],
                        center: UnitPoint(x: 0.35, y: 0.30),
                        startRadius: 4,
                        endRadius: core * 0.6
                    )
                )
                .frame(width: core, height: core)
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.15), lineWidth: 1)
                )
        }
        .frame(width: halo, height: halo)
    }

    // MARK: Begin button (same violet pill as BreathHomeView)

    private var beginButton: some View {
        Button { onBegin() } label: {
            Text("Begin")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [
                            Color(hue: 270.0 / 360.0, saturation: 0.55, brightness: 0.55),
                            Color(hue: 280.0 / 360.0, saturation: 0.50, brightness: 0.45),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(
                    color: Color(hue: 270.0 / 360.0, saturation: 0.5, brightness: 0.4).opacity(0.4),
                    radius: 14, x: 0, y: 6
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Animated session

private struct AnimatedSessionView: View {
    let technique: Technique
    let muted: Bool
    let onComplete: () -> Void

    @StateObject private var controller = SessionController()

    var body: some View {
        ZStack {
            BreathAnimationView(
                currentPhase: controller.currentPhase,
                progress: controller.phaseProgress
            )
            .ignoresSafeArea()

            VStack {
                Spacer()
                phaseLabelStack
                    .padding(.bottom, 96)
            }
        }
        .onAppear {
            controller.start(technique: technique, muted: muted)
        }
        .onDisappear {
            controller.stop()
        }
        .onChange(of: controller.isComplete) { _, complete in
            if complete { onComplete() }
        }
    }

    /// Two-line phase label: current action in a calm serif as the heading,
    /// next action smaller and dimmer below. Matches the Mac app's
    /// "Inhale / then hold" visual hierarchy (ROADMAP #4).
    private var phaseLabelStack: some View {
        VStack(spacing: 6) {
            if let label = controller.currentLabel {
                Text(label)
                    .font(.system(size: 40, weight: .light, design: .serif))
                    .foregroundStyle(.white.opacity(0.92))
                    .animation(.easeInOut(duration: 0.35), value: label)
            }
            if let nextLabel = controller.nextLabel {
                Text("then \(nextLabel.lowercased())")
                    .font(.system(.callout, design: .serif))
                    .foregroundStyle(.white.opacity(0.45))
                    .animation(.easeInOut(duration: 0.35), value: nextLabel)
            }
        }
    }
}

/// Drives the session timeline: phases, rounds, audio, haptics.
@MainActor
private class SessionController: ObservableObject {
    @Published var currentPhase: BreathPhase?
    @Published var currentLabel: String?
    /// One-line preview of the next action. Drives the secondary label so
    /// the user always knows what's coming without counting.
    @Published var nextLabel: String?
    @Published var phaseProgress: Double = 0
    @Published var isComplete = false

    private var displayLink: CADisplayLink?
    private var startTime: TimeInterval = 0
    private var elapsed: TimeInterval = 0
    private var technique: Technique?
    private var audioPlayer: AVAudioPlayer?

    func start(technique: Technique, muted: Bool) {
        self.technique = technique
        startTime = CACurrentMediaTime()
        // Audio playback deferred to #18 (mp3 bundle). muted flag stored
        // here so the audio layer can respect it once tracks are wired.
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        audioPlayer?.stop()
        audioPlayer = nil
    }

    @objc private func tick() {
        guard let technique = technique else { return }
        let now = CACurrentMediaTime()
        elapsed = now - startTime

        if elapsed >= technique.duration {
            isComplete = true
            stop()
            return
        }

        switch technique {
        case .breathing(let t):
            updateBreathingPhase(t)
        case .mindfulness(let t):
            updateMindfulnessPhase(t)
        }
    }

    private func updateBreathingPhase(_ t: BreathingTechnique) {
        let cycleLength = t.phases.map(\.duration).reduce(0, +)
        let timeInCycle = elapsed.truncatingRemainder(dividingBy: cycleLength)

        var accumulated: TimeInterval = 0
        for (idx, phase) in t.phases.enumerated() {
            if timeInCycle < accumulated + phase.duration {
                let phaseElapsed = timeInCycle - accumulated
                currentPhase = phase
                currentLabel = phase.label
                let nextIdx = (idx + 1) % t.phases.count
                nextLabel = t.phases[nextIdx].label
                phaseProgress = phaseElapsed / phase.duration

                if phaseElapsed < 0.05 {
                    fireHaptic(for: phase.type)
                }
                return
            }
            accumulated += phase.duration
        }
    }

    private func updateMindfulnessPhase(_ t: MindfulnessTechnique) {
        var accumulated: TimeInterval = 0
        for (idx, prompt) in t.prompts.enumerated() {
            if elapsed < accumulated + prompt.duration {
                let phaseElapsed = elapsed - accumulated
                currentLabel = prompt.text
                nextLabel = idx + 1 < t.prompts.count ? t.prompts[idx + 1].text : nil
                phaseProgress = phaseElapsed / prompt.duration
                return
            }
            accumulated += prompt.duration
        }
    }

    private func fireHaptic(for phaseType: BreathPhase.PhaseType) {
        switch phaseType {
        case .inhale, .exhale:
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        case .hold:
            break
        }
    }
}

// MARK: - Breath animation

private struct BreathAnimationView: View {
    let currentPhase: BreathPhase?
    let progress: Double

    private let haloColor = Color(hue: 350.0 / 360.0, saturation: 0.35, brightness: 0.85)

    var body: some View {
        GeometryReader { geo in
            let restSize = min(geo.size.width, geo.size.height) * 0.92
            ZStack {
                // Outer halo: soft rose glow that anchors the orb
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                haloColor.opacity(0.22),
                                haloColor.opacity(0.0),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: restSize * 0.7
                        )
                    )
                    .frame(width: restSize * 1.4, height: restSize * 1.4)
                    .scaleEffect(scale)
                    .blur(radius: 18)

                // Core orb: pearl rose with highlight up-left, deep mauve
                // edge — same palette as BreathHomeView and the Mac calm orb.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 1.00, green: 0.96, blue: 0.96),
                                Color(red: 0.95, green: 0.80, blue: 0.83),
                                Color(red: 0.55, green: 0.34, blue: 0.42),
                            ],
                            center: UnitPoint(x: 0.38, y: 0.32),
                            startRadius: 0,
                            endRadius: restSize / 2
                        )
                    )
                    .frame(width: restSize, height: restSize)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
                    .scaleEffect(scale)
                    .shadow(color: haloColor.opacity(0.35), radius: 40, x: 0, y: 0)
                    .animation(.easeInOut(duration: 0.6), value: scale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var scale: Double {
        guard let phase = currentPhase else { return 0.55 }
        switch phase.type {
        case .inhale: return 0.55 + (progress * 0.45)
        case .hold:   return 1.0
        case .exhale: return 1.0 - (progress * 0.45)
        }
    }
}

// MARK: - Post-session mood capture

private struct PostSessionView: View {
    let technique: Technique
    let onDone: (Int?) -> Void

    @State private var selectedMood: Int?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                calmOrbView

                VStack(spacing: 8) {
                    Text("Session complete")
                        .font(.system(.title, design: .serif))
                        .foregroundStyle(.white)
                    Text(technique.name)
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Spacer(minLength: 32)

            VStack(spacing: 16) {
                Text("How do you feel?")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))

                HStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { mood in
                        moodButton(mood)
                    }
                }
                .padding(.horizontal, 24)

                Text("1 = worse, 5 = much better")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            VStack(spacing: 12) {
                doneButton
                    .padding(.horizontal, 24)

                Button("Skip") { onDone(nil) }
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
                    .buttonStyle(.plain)
            }
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func moodButton(_ mood: Int) -> some View {
        let isSelected = selectedMood == mood
        return Button { selectedMood = mood } label: {
            Text("\(mood)")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(
                    ZStack {
                        if isSelected {
                            Circle().fill(
                                LinearGradient(
                                    colors: [
                                        Color(hue: 270.0 / 360.0, saturation: 0.55, brightness: 0.55),
                                        Color(hue: 280.0 / 360.0, saturation: 0.50, brightness: 0.45),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        } else {
                            Circle().fill(Color.white.opacity(0.08))
                        }
                    }
                )
                .overlay(
                    Circle().strokeBorder(
                        isSelected ? Color.white.opacity(0.4) : Color.white.opacity(0.18),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }

    private var doneButton: some View {
        Button { onDone(selectedMood) } label: {
            Text("Done")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [
                            Color(hue: 270.0 / 360.0, saturation: 0.55, brightness: 0.55),
                            Color(hue: 280.0 / 360.0, saturation: 0.50, brightness: 0.45),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .shadow(
                    color: Color(hue: 270.0 / 360.0, saturation: 0.5, brightness: 0.4).opacity(0.4),
                    radius: 14, x: 0, y: 6
                )
        }
        .buttonStyle(.plain)
    }

    // Smaller calmed version of the home view orb (120pt core vs 240pt).
    private var calmOrbView: some View {
        let core: CGFloat = 120
        let halo: CGFloat = core * 1.05
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hue: 350.0 / 360.0, saturation: 0.35, brightness: 0.85).opacity(0.25),
                            Color(hue: 350.0 / 360.0, saturation: 0.20, brightness: 0.40).opacity(0.0),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: halo * 0.55
                    )
                )
                .frame(width: halo, height: halo)
                .blur(radius: 6)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.00, green: 0.96, blue: 0.96),
                            Color(red: 0.95, green: 0.80, blue: 0.83),
                            Color(red: 0.55, green: 0.34, blue: 0.42),
                        ],
                        center: UnitPoint(x: 0.35, y: 0.30),
                        startRadius: 2,
                        endRadius: core * 0.6
                    )
                )
                .frame(width: core, height: core)
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.15), lineWidth: 1)
                )
        }
        .frame(width: halo, height: halo)
    }
}

#Preview {
    BreathSessionView(
        technique: allTechniques[0],
        onDismiss: {}
    )
}
