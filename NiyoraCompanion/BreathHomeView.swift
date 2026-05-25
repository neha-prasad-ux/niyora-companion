import SwiftUI

/// Home screen for the iOS app. Mirrors the Mac app's pre-session info
/// screen: top status row with profile + wordmark + mute, a big stress
/// orb, technique name + subtitle, a violet "Begin" CTA, and a
/// secondary "Try a different one" link that rotates through unlocked
/// techniques.
///
/// Replaces the BreathTabView list. v1 has no PPG / stress signals on
/// iOS, so the orb uses the calm-state gradient by default. When the
/// user later pairs with a Mac that has a real score, we can switch
/// this to read from the paired-Mac status update.
struct BreathHomeView: View {

    /// Initial random unlocked technique. Reseeded on app launch and
    /// when the user taps "Try a different one".
    @State private var technique: Technique
    @State private var showSession = false
    @State private var showMySoul = false
    @State private var muted = false
    @State private var completedSessions: Int

    init() {
        let count = LocalSessionStore.completedCount()
        let tier = Tier.current(completedSessions: count)
        let unlocked = unlockedTechniques(tier: tier)
        _technique = State(initialValue: unlocked.randomElement() ?? allTechniques[0])
        _completedSessions = State(initialValue: count)
    }

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                tagline
                    .padding(.top, 6)

                Spacer(minLength: 0)

                orbView

                Spacer(minLength: 0)

                techniqueText
                    .padding(.bottom, 18)

                actions
                    .padding(.horizontal, 24)
            }
        }
        .preferredColorScheme(.dark)
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
        .sheet(isPresented: $showMySoul) {
            MySoulSheet(completedSessions: completedSessions)
        }
    }

    // MARK: - Top status row

    private var topBar: some View {
        HStack {
            Button {
                showMySoul = true
            } label: {
                Image(systemName: "person")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 6) {
                // Niyora wordmark dot. Solid filled circle; the radio
                // "outlined" look in the reference is the focus ring
                // around a small disc.
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

    private var tagline: some View {
        Text("Calm in 60 seconds")
            .font(.system(size: 12, weight: .light))
            .foregroundStyle(.white.opacity(0.45))
            .tracking(0.3)
    }

    // MARK: - Orb

    private var orbView: some View {
        let core: CGFloat = 240
        let halo: CGFloat = core * 1.3
        return ZStack {
            // Outer halo
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
                .blur(radius: 14)

            // Core orb (pearl rose: bright highlight upper-left,
            // mid rose body, deep mauve edge — same palette as the
            // Mac app's calm-state stress ball).
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.00, green: 0.96, blue: 0.96),       // highlight
                            Color(red: 0.95, green: 0.80, blue: 0.83),       // mid rose
                            Color(red: 0.55, green: 0.34, blue: 0.42),       // edge mauve
                        ],
                        center: UnitPoint(x: 0.35, y: 0.30),
                        startRadius: 4,
                        endRadius: core * 0.6
                    )
                )
                .frame(width: core, height: core)
                .shadow(color: Color(red: 0.7, green: 0.4, blue: 0.5).opacity(0.35), radius: 38, x: 0, y: 14)
                .overlay(
                    // Subtle inner edge darkening for depth
                    Circle()
                        .strokeBorder(Color.black.opacity(0.15), lineWidth: 1)
                )
        }
    }

    // MARK: - Technique label

    private var techniqueText: some View {
        VStack(spacing: 6) {
            Text(technique.name)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(techniqueSubtitle)
                .font(.system(size: 13, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    /// Shortened subtitle: "<intent> <duration>s" so the line stays calm.
    private var techniqueSubtitle: String {
        let durationSec = Int(technique.duration.rounded())
        // Strip any trailing "· Ns" from the existing subtitle so we
        // don't double up.
        let raw = technique.subtitle
        let cleaned: String
        if let dotIdx = raw.range(of: "·") {
            cleaned = String(raw[..<dotIdx.lowerBound]).trimmingCharacters(in: .whitespaces)
        } else {
            cleaned = raw
        }
        return "\(cleaned) \(durationSec)s"
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 14) {
            Button {
                showSession = true
            } label: {
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
                    .shadow(color: Color(hue: 270.0 / 360.0, saturation: 0.5, brightness: 0.4).opacity(0.4), radius: 14, x: 0, y: 6)
            }
            .buttonStyle(.plain)

            Button {
                rotateTechnique()
            } label: {
                Text("Try a different one")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 4)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Rotation

    private func rotateTechnique() {
        let tier = Tier.current(completedSessions: completedSessions)
        let pool = unlockedTechniques(tier: tier).filter { $0 != technique }
        if let next = pool.randomElement() {
            technique = next
        }
    }
}

/// Light placeholder presentation of MySoulTabView in a sheet from the
/// top-left person icon. Keeps the My Soul surface reachable without
/// the bottom tab bar.
private struct MySoulSheet: View {
    let completedSessions: Int
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

private let backgroundGradient = LinearGradient(
    colors: [
        Color(hue: 280.0 / 360.0, saturation: 0.25, brightness: 0.05),
        Color(hue: 270.0 / 360.0, saturation: 0.20, brightness: 0.02),
        Color.black,
    ],
    startPoint: .top,
    endPoint: .bottom
)

#Preview {
    BreathHomeView()
}
