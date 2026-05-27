import SwiftUI
import AVFoundation

/// Full breath session flow: pre-session info → animated session →
/// post-session mood capture. Persists the completed session via
/// LocalSessionStore on completion.
struct BreathSessionView: View {
    let technique: Technique
    let onDismiss: () -> Void

    @State private var phase: Phase = .pre
    @State private var audioChoice: AudioTrack = .random

    enum Phase {
        case pre
        case session
        case post
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch phase {
            case .pre:
                PreSessionView(
                    technique: technique,
                    audioChoice: $audioChoice,
                    onBegin: {
                        phase = .session
                    },
                    onCancel: onDismiss
                )
            case .session:
                AnimatedSessionView(
                    technique: technique,
                    audioTrack: audioChoice,
                    onComplete: {
                        phase = .post
                    }
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

// MARK: - Pre-session info screen

private struct PreSessionView: View {
    let technique: Technique
    @Binding var audioChoice: AudioTrack
    let onBegin: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Text(technique.name)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)
                Text(technique.subtitle)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
            }

            VStack(alignment: .leading, spacing: 16) {
                InfoBlock(title: "Instructions", text: technique.instructions)
                InfoBlock(title: "Benefits", text: technique.benefits)
            }
            .padding(.horizontal, 24)

            VStack(spacing: 12) {
                Text("Ambient audio")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                Picker("Audio", selection: $audioChoice) {
                    ForEach(AudioTrack.allCases) { track in
                        Text(track.displayName).tag(track)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
            }

            Spacer()

            VStack(spacing: 12) {
                Button("Begin") {
                    onBegin()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)

                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

private struct InfoBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
            Text(text)
                .font(.body)
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Animated session

private struct AnimatedSessionView: View {
    let technique: Technique
    let audioTrack: AudioTrack
    let onComplete: () -> Void

    @StateObject private var controller = SessionController()

    var body: some View {
        ZStack {
            // Niyora background: near-black with a faint indigo cast,
            // matching the Mac app's session canvas backdrop.
            LinearGradient(
                colors: [
                    Color(hue: 250.0 / 360.0, saturation: 0.35, brightness: 0.04),
                    Color(hue: 260.0 / 360.0, saturation: 0.20, brightness: 0.02),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            BreathAnimationView(
                technique: technique,
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
            controller.start(technique: technique, audioTrack: audioTrack)
        }
        .onDisappear {
            controller.stop()
        }
        .onChange(of: controller.isComplete) { _, complete in
            if complete {
                onComplete()
            }
        }
    }

    /// Two-line phase label: the current action in a calm serif as the
    /// heading, the next action smaller and dimmer below. Matches the Mac
    /// app's "Inhale / then hold" visual hierarchy (ROADMAP #4).
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
    /// One-line preview of the next action ("then exhale", "then inhale").
    /// Drives the secondary line below the current phase label so the user
    /// always knows what's coming without having to count.
    @Published var nextLabel: String?
    @Published var phaseProgress: Double = 0
    @Published var isComplete = false

    private var displayLink: CADisplayLink?
    private var startTime: TimeInterval = 0
    private var elapsed: TimeInterval = 0

    private var technique: Technique?
    private var audioPlayer: AVAudioPlayer?

    func start(technique: Technique, audioTrack: AudioTrack) {
        self.technique = technique
        startTime = CACurrentMediaTime()

        // Start audio; if Random, pick one of the bundled tracks at random
        let resolvedTrack: AudioTrack = audioTrack == .random
            ? ([.serene, .ocean, .forest].randomElement() ?? .serene)
            : audioTrack
        playAudio(track: resolvedTrack)

        // Start animation loop
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

        // Check if complete
        if elapsed >= technique.duration {
            isComplete = true
            stop()
            return
        }

        // Determine current phase and progress
        switch technique {
        case .breathing(let t):
            updateBreathingPhase(t)
        case .mindfulness(let t):
            updateMindfulnessPhase(t)
        }
    }

    private func updateBreathingPhase(_ t: BreathingTechnique) {
        let cycleLength = t.phases.map(\.duration).reduce(0, +)
        let totalElapsed = elapsed
        let timeInCycle = totalElapsed.truncatingRemainder(dividingBy: cycleLength)

        var accumulated: TimeInterval = 0
        for (idx, phase) in t.phases.enumerated() {
            if timeInCycle < accumulated + phase.duration {
                let phaseElapsed = timeInCycle - accumulated
                currentPhase = phase
                currentLabel = phase.label
                // Next phase wraps to the first phase of the next cycle.
                let nextIdx = (idx + 1) % t.phases.count
                nextLabel = t.phases[nextIdx].label
                phaseProgress = phaseElapsed / phase.duration

                // Fire haptic on phase transitions
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
                // Mindfulness prompts do not loop. The last prompt has no next.
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

    private func playAudio(track: AudioTrack) {
        guard let url = track.url else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1
            audioPlayer?.play()
        } catch {
            print("Audio playback failed: \(error)")
        }
    }
}

// MARK: - Breath animation

private struct BreathAnimationView: View {
    let technique: Technique
    let currentPhase: BreathPhase?
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            // The orb's resting size is the smaller dimension of the canvas
            // (gives a generous, near-fullscreen presence). Scale modulates
            // between 0.55 (fully exhaled) and 1.0 (fully inhaled).
            let restSize = min(geo.size.width, geo.size.height) * 0.92
            ZStack {
                // Outer halo: very soft, large, low-opacity glow that
                // anchors the orb without competing with it.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                currentColor.opacity(0.22),
                                currentColor.opacity(0.0),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: restSize * 0.7
                        )
                    )
                    .frame(width: restSize * 1.4, height: restSize * 1.4)
                    .scaleEffect(scale)
                    .blur(radius: 18)

                // Core orb with depth: bright highlight up-left, deeper
                // edge bottom-right, matching the Mac app's planet feel.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                currentColor.opacity(0.95),
                                currentColor.opacity(0.55),
                                currentColor.opacity(0.15),
                            ],
                            center: UnitPoint(x: 0.38, y: 0.32),
                            startRadius: 0,
                            endRadius: restSize / 2
                        )
                    )
                    .frame(width: restSize, height: restSize)
                    .scaleEffect(scale)
                    .shadow(color: currentColor.opacity(0.45), radius: 40, x: 0, y: 0)
                    .animation(.easeInOut(duration: 0.6), value: scale)
                    .animation(.easeInOut(duration: 0.6), value: currentColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var currentColor: Color {
        guard let phase = currentPhase else {
            return Color(hue: technique.visual.inhaleColor.h / 360.0,
                        saturation: technique.visual.inhaleColor.s / 100.0,
                        brightness: technique.visual.inhaleColor.l / 100.0)
        }

        let phaseColor: PhaseColor = {
            switch phase.type {
            case .inhale: return technique.visual.inhaleColor
            case .hold: return technique.visual.holdColor
            case .exhale: return technique.visual.exhaleColor
            }
        }()

        let brightness = (phaseColor.l / 100.0) + technique.visual.brightnessBoost
        return Color(hue: phaseColor.h / 360.0,
                    saturation: phaseColor.s / 100.0,
                    brightness: brightness)
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
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                Text("Session complete")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white)
                Text(technique.name)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
            }

            VStack(spacing: 16) {
                Text("How do you feel?")
                    .font(.headline)
                    .foregroundStyle(.white)

                HStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { mood in
                        Button {
                            selectedMood = mood
                        } label: {
                            Circle()
                                .strokeBorder(selectedMood == mood ? Color.white : Color.white.opacity(0.3), lineWidth: 2)
                                .background(Circle().fill(selectedMood == mood ? Color.white.opacity(0.2) : Color.clear))
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Text("\(mood)")
                                        .font(.title3.weight(.medium))
                                        .foregroundStyle(.white)
                                )
                        }
                    }
                }
                .padding(.horizontal, 24)

                Text("1 = worse, 5 = much better")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            VStack(spacing: 12) {
                Button("Done") {
                    onDone(selectedMood)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)

                Button("Skip") {
                    onDone(nil)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - Audio tracks

enum AudioTrack: String, CaseIterable, Identifiable {
    case random
    case serene
    case ocean
    case forest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .random: return "Random"
        case .serene: return "Serene"
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        }
    }

    var url: URL? {
        switch self {
        case .random: return nil
        case .serene: return Bundle.main.url(forResource: "serene", withExtension: "mp3")
        case .ocean: return Bundle.main.url(forResource: "ocean", withExtension: "mp3")
        case .forest: return Bundle.main.url(forResource: "forest", withExtension: "mp3")
        }
    }
}

#Preview {
    BreathSessionView(
        technique: allTechniques[0],
        onDismiss: {}
    )
}
