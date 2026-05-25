import SwiftUI

/// Breath tab: lists all 14 techniques (breathing + mindfulness). Locked
/// techniques show "Unlocks at <Tier>". Selecting a technique opens the
/// session flow (pre-info → animated session → mood capture).
///
/// Visual language matches the Mac app: near-black background with a faint
/// indigo cast, serif headings, card rows with tier-coloured locks.
struct BreathTabView: View {
    @State private var selectedTechnique: Technique?
    @State private var completedSessions: Int = 0

    var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                        .padding(.top, 8)

                    TierProgressView(completedSessions: completedSessions)

                    sectionStack(title: "Breathing", techniques: breathingTechniques)
                    sectionStack(title: "Mindfulness", techniques: mindfulnessTechniques)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .onAppear {
            completedSessions = LocalSessionStore.completedCount()
        }
        .fullScreenCover(item: $selectedTechnique) { technique in
            BreathSessionView(
                technique: technique,
                onDismiss: {
                    selectedTechnique = nil
                    completedSessions = LocalSessionStore.completedCount()
                }
            )
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Breath")
                .font(.system(size: 36, weight: .light, design: .serif))
                .foregroundStyle(.white)
            Text("Calm in 60 seconds.")
                .font(.system(.subheadline, design: .serif))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionStack(title: String, techniques: [Technique]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.subheadline, design: .serif).weight(.medium))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.leading, 4)

            VStack(spacing: 8) {
                ForEach(techniques) { technique in
                    TechniqueRow(
                        technique: technique,
                        isUnlocked: isUnlocked(technique),
                        onTap: {
                            if isUnlocked(technique) {
                                selectedTechnique = technique
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Style

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hue: 250.0 / 360.0, saturation: 0.35, brightness: 0.06),
                Color(hue: 260.0 / 360.0, saturation: 0.20, brightness: 0.03),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Data

    private var breathingTechniques: [Technique] {
        allTechniques.filter {
            if case .breathing = $0 { return true }
            return false
        }
    }

    private var mindfulnessTechniques: [Technique] {
        allTechniques.filter {
            if case .mindfulness = $0 { return true }
            return false
        }
    }

    private func isUnlocked(_ technique: Technique) -> Bool {
        let currentTier = Tier.current(completedSessions: completedSessions)
        return unlockedTechniques(tier: currentTier).contains(technique)
    }
}

// MARK: - Technique row

/// A single technique card. Locked rows render dimmed with a tier-coloured
/// lock chip ("Unlocks at <Tier>"). Unlocked rows show a soft chevron.
private struct TechniqueRow: View {
    let technique: Technique
    let isUnlocked: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(technique.name)
                        .font(.system(.title3, design: .serif))
                        .foregroundStyle(isUnlocked ? .white : Color.white.opacity(0.45))

                    Text(technique.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(isUnlocked ? 0.55 : 0.30))

                    if !isUnlocked {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                            Text("Unlocks at \(technique.unlockTier.name)")
                                .font(.caption2)
                        }
                        .foregroundStyle(technique.unlockTier.color.opacity(0.85))
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 8)
                if isUnlocked {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(isUnlocked ? 0.05 : 0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
    }
}

// MARK: - Tier progress

/// Compact tier card pinned above the technique sections. Shows the
/// current Soul tier (colored chip) and the count to the next tier.
private struct TierProgressView: View {
    let completedSessions: Int

    var body: some View {
        let current = Tier.current(completedSessions: completedSessions)
        let next = next(after: current)

        HStack(spacing: 14) {
            Circle()
                .fill(current.color)
                .frame(width: 32, height: 32)
                .shadow(color: current.color.opacity(0.6), radius: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text("Your Soul")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Text(current.name)
                    .font(.system(.title3, design: .serif))
                    .foregroundStyle(.white)
            }

            Spacer(minLength: 8)

            if let (nextTier, remaining) = next {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Next: \(nextTier.name)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                    Text("\(remaining) to go")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(nextTier.color.opacity(0.85))
                }
            } else {
                Text("Max tier")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func next(after current: Tier) -> (Tier, Int)? {
        let all: [Tier] = [.spark, .glow, .shine, .radiance, .brilliance]
        guard let idx = all.firstIndex(of: current), idx < all.count - 1 else {
            return nil
        }
        let n = all[idx + 1]
        return (n, max(0, n.threshold - completedSessions))
    }
}

#Preview {
    BreathTabView()
        .preferredColorScheme(.dark)
}
