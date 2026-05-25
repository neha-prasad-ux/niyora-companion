import SwiftUI

/// Niyora home (pre-session) screen for iOS.
///
/// Layout contract (top-to-bottom in a single VStack):
///   header → flex spacer → orb → label → flex spacer → actions
///
/// SwiftUI's default safe-area handling anchors the VStack inside the
/// status bar at the top and the home indicator at the bottom. Two
/// greedy `Spacer`s split the leftover vertical real-estate evenly
/// around the orb so the screen never has a single big "dead zone"
/// at one edge.
struct BreathHomeView: View {

    @State private var technique: Technique
    @State private var showSession = false
    @State private var showMySoul = false
    @State private var muted = false
    @State private var completedSessions: Int
    @State private var breathPhase: CGFloat = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        let count = LocalSessionStore.completedCount()
        let tier = Tier.current(completedSessions: count)
        let unlocked = unlockedTechniques(tier: tier)
        _technique = State(initialValue: unlocked.randomElement() ?? allTechniques[0])
        _completedSessions = State(initialValue: count)
    }

    var body: some View {
        ZStack {
            BackgroundLayer()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 8)
                orb
                techniqueLabel
                    .padding(.top, 18)
                    .padding(.horizontal, 24)
                Spacer(minLength: 8)
                actions
                    .padding(.horizontal, 24)
            }
        }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .onAppear(perform: startBreathingLoop)
        .fullScreenCover(isPresented: $showSession) {
            BreathSessionView(
                technique: technique,
                onDismiss: {
                    showSession = false
                    completedSessions = LocalSessionStore.completedCount()
                    rotateTechnique()
                }
            )
        }
        .fullScreenCover(isPresented: $showMySoul) {
            MySoulSheet()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            ZStack {
                // Centered wordmark
                HStack(spacing: 7) {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.7), lineWidth: 1.2)
                        .frame(width: 11, height: 11)
                        .overlay(
                            Circle()
                                .fill(Color.white.opacity(0.85))
                                .frame(width: 4, height: 4)
                        )
                    Text("NIYORA")
                        .font(.system(size: 13, weight: .medium))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("Niyora")

                // Left + right icon buttons overlay
                HStack {
                    Button {
                        showMySoul = true
                    } label: {
                        Image(systemName: "person")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(.white.opacity(0.65))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("My Soul")

                    Spacer()

                    Button {
                        muted.toggle()
                        Haptics.selection()
                    } label: {
                        Image(systemName: muted ? "speaker.slash" : "speaker.wave.2")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(.white.opacity(0.65))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(muted ? "Unmute" : "Mute")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)

            Text("Calm in 60 seconds")
                .font(.system(size: 11, weight: .light))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Orb

    /// Fixed 210pt orb. Largest hero size that lets the BEGIN button
    /// clear the iPhone 17 Pro bottom safe area without clipping.
    /// Anything bigger (220+) starts cutting into the BEGIN curve.
    private var orb: some View {
        let core: CGFloat = 210
        let halo: CGFloat = core * 1.15

        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            BrandColors.orbGlow.opacity(0.35),
                            BrandColors.orbGlow.opacity(0.12),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: core * 0.45,
                        endRadius: halo * 0.5
                    )
                )
                .frame(width: halo, height: halo)
                .blur(radius: 14)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            BrandColors.orbHighlight,
                            BrandColors.orbMid,
                            BrandColors.orbEdge
                        ],
                        center: UnitPoint(x: 0.35, y: 0.30),
                        startRadius: 0,
                        endRadius: core * 0.55
                    )
                )
                .overlay(
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.45),
                                    Color.white.opacity(0.18),
                                    Color.clear
                                ],
                                center: UnitPoint(x: 0.28, y: 0.22),
                                startRadius: 0,
                                endRadius: core * 0.42
                            )
                        )
                )
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.25), lineWidth: 10)
                        .blur(radius: 10)
                        .offset(x: -6, y: -4)
                        .mask(Circle())
                )
                .frame(width: core, height: core)
                .shadow(color: BrandColors.orbGlow.opacity(0.5), radius: 18, x: 0, y: 0)
        }
        .frame(width: halo, height: halo)
        .scaleEffect(breathPhase)
        .accessibilityHidden(true)
    }

    private func startBreathingLoop() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 5.5).repeatForever(autoreverses: true)) {
            breathPhase = 1.04
        }
    }

    // MARK: - Technique label

    private var techniqueLabel: some View {
        VStack(spacing: 6) {
            Text(technique.name)
                .font(.system(size: 24, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(.white.opacity(0.95))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            Text(techniqueSubtitle)
                .font(.system(size: 13, weight: .light))
                .tracking(0.3)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var techniqueSubtitle: String {
        let durationSec = Int(technique.duration.rounded())
        let raw = technique.subtitle
        let cleaned: String
        if let dotIdx = raw.range(of: "·") {
            cleaned = String(raw[..<dotIdx.lowerBound]).trimmingCharacters(in: .whitespaces)
        } else {
            cleaned = raw
        }
        return "\(cleaned) · \(durationSec)s"
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 14) {
            Button {
                Haptics.selection()
                rotateTechnique()
            } label: {
                Text("Try a different one")
                    .font(.system(size: 13, weight: .light))
                    .tracking(0.4)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Choose another technique")

            Button {
                Haptics.impact(.soft)
                showSession = true
            } label: {
                Text("BEGIN")
                    .font(.system(size: 15, weight: .medium))
                    .tracking(2.0)
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [BrandColors.beginTop, BrandColors.beginBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(BrandColors.beginBorder, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: BrandColors.beginGlow.opacity(0.35), radius: 18, x: 0, y: 4)
            }
            .buttonStyle(BeginButtonStyle())
            .accessibilityLabel("Begin \(technique.name)")
        }
    }

    private func rotateTechnique() {
        let tier = Tier.current(completedSessions: completedSessions)
        let pool = unlockedTechniques(tier: tier).filter { $0 != technique }
        if let next = pool.randomElement() {
            technique = next
        }
    }
}

// MARK: - Background

private struct BackgroundLayer: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(hue: 250.0 / 360.0, saturation: 0.30, brightness: 0.06),
                Color(hue: 260.0 / 360.0, saturation: 0.20, brightness: 0.03),
                .black
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Begin button style

private struct BeginButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Brand colors (calm-tier palette ported from Mac App.css)

private enum BrandColors {
    static let orbHighlight = Color.white.opacity(0.97)
    static let orbMid       = Color(hue: 220.0 / 360.0, saturation: 0.045, brightness: 0.94)
    static let orbEdge      = Color(hue: 220.0 / 360.0, saturation: 0.27,  brightness: 0.83)
    static let orbGlow      = Color(hue: 220.0 / 360.0, saturation: 0.31,  brightness: 0.89)

    static let beginTop    = Color(hue: 270.0 / 360.0, saturation: 0.67, brightness: 0.675).opacity(0.95)
    static let beginBottom = Color(hue: 280.0 / 360.0, saturation: 0.57, brightness: 0.49).opacity(0.95)
    static let beginBorder = Color(hue: 270.0 / 360.0, saturation: 0.36, brightness: 0.71).opacity(0.30)
    static let beginGlow   = Color(hue: 270.0 / 360.0, saturation: 0.50, brightness: 0.40)
}

// MARK: - Haptics

private enum Haptics {
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

// MARK: - My Soul sheet

private struct MySoulSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MySoulTabView(flow: .constant(PairingFlow()))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    BreathHomeView()
}
