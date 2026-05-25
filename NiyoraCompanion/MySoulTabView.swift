import SwiftUI

/// My Soul screen: presented full-screen from the home view's profile
/// icon. Shows the current Soul tier as a 3D orb (matching the home
/// view's rose orb language but coloured per tier) with Saturn-style
/// rings per tier count, plus tier name and progression to next.
///
/// Brand language ports from the Mac app's My Soul panel (see
/// niyora/app/src/Settings.tsx soul-planet + soul-ring styling).
///
/// Session history and embedded settings (reminders, pair status,
/// privacy footer) per the v1 spec are tracked separately in
/// niyora-companion#34 and will land in a follow-up pass.
struct MySoulTabView: View {
    @Binding var flow: PairingFlow
    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [LocalSessionStore.Session] = []

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 16)

                tierOrb

                Spacer(minLength: 12)

                tierLabel
                    .padding(.bottom, 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
        .onAppear { loadData() }
    }

    // MARK: - Top bar

    /// Mirrors `BreathHomeView.topBar` (profile · wordmark · close icon)
    /// so the screen feels like a continuation of the home view.
    private var topBar: some View {
        HStack(spacing: 0) {
            // Left placeholder to keep the wordmark visually centered.
            Color.clear.frame(width: 44, height: 44)

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
                Text("My Soul")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Tier orb (3D rose-style, coloured per tier, with rings)

    private var tierOrb: some View {
        let core: CGFloat = 240
        let halo: CGFloat = core * 1.05
        let accent = effectiveTier.color
        return ZStack {
            // Soft outer halo in the tier accent
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accent.opacity(0.30), accent.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: halo * 0.55
                    )
                )
                .frame(width: halo, height: halo)
                .blur(radius: 6)

            // Core orb with depth: bright highlight upper-left, mid
            // tier-coloured body, deep edge. Same gradient pattern as
            // the home view's rose orb, just remapped to tier hues.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            accent.opacity(0.95),
                            accent.opacity(0.55),
                            accent.opacity(0.15),
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

            // Saturn-style rings per tier count (Spark 0, Glow 1, Shine
            // 2, Radiance 3, Brilliance 4). Matches Mac Settings.tsx.
            ForEach(0..<ringCount, id: \.self) { i in
                Ellipse()
                    .stroke(accent.opacity(0.55 - Double(i) * 0.08), lineWidth: 1.4)
                    .frame(
                        width: core + CGFloat(i * 18) + 28,
                        height: 28 + CGFloat(i * 4)
                    )
                    .shadow(color: accent.opacity(0.20), radius: 6)
            }
        }
    }

    private var ringCount: Int {
        switch effectiveTier {
        case .spark:      return 0
        case .glow:       return 1
        case .shine:      return 2
        case .radiance:   return 3
        case .brilliance: return 4
        }
    }

    // MARK: - Tier label

    private var tierLabel: some View {
        VStack(spacing: 8) {
            Text(effectiveTier.name)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(effectiveTier.color)

            Text("\(effectiveSessionCount) session\(effectiveSessionCount == 1 ? "" : "s")")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(.white.opacity(0.5))

            if let remaining = effectiveTier.sessionsToNext(currentCount: effectiveSessionCount),
               let next = Tier(rawValue: effectiveTier.rawValue + 1) {
                Text("\(remaining) more to \(next.name)")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 6)
            } else {
                Text("Maximum tier reached")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 6)
            }

            Text(isSyncedFromMac ? "Synced from Mac" : "Local only")
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.top, 4)
        }
    }

    private var isSyncedFromMac: Bool {
        flow.macTier != nil
    }

    private var effectiveSessionCount: Int {
        flow.macSessionCount ?? sessions.filter(\.completed).count
    }

    private var effectiveTier: Tier {
        flow.macTier ?? Tier.forSessionCount(effectiveSessionCount)
    }

    // MARK: - Data

    private func loadData() {
        sessions = LocalSessionStore.all()
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
    MySoulTabView(flow: .constant(PairingFlow()))
}
