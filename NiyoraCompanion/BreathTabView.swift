import SwiftUI

/// Breath tab: lists all 14 techniques (breathing + mindfulness).
/// Locked techniques show "Unlocks at <Tier>". Selecting a technique
/// opens the session flow (pre-info → animated session → mood capture).
struct BreathTabView: View {
    @State private var selectedTechnique: Technique?
    @State private var completedSessions: Int = 0

    var body: some View {
        NavigationStack {
            List {
                Section("Breathing") {
                    ForEach(breathingTechniques) { technique in
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

                Section("Mindfulness") {
                    ForEach(mindfulnessTechniques) { technique in
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

                Section {
                    TierProgressView(completedSessions: completedSessions)
                }
            }
            .navigationTitle("Breath")
            .onAppear {
                completedSessions = LocalSessionStore.completedCount()
            }
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

/// A single technique row. Shows lock icon + "Unlocks at <Tier>"
/// if not yet unlocked.
private struct TechniqueRow: View {
    let technique: Technique
    let isUnlocked: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(technique.name)
                        .font(.headline)
                        .foregroundStyle(isUnlocked ? .primary : .secondary)
                    Text(technique.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !isUnlocked {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                            Text("Unlocks at \(technique.unlockTier.name)")
                                .font(.caption2)
                        }
                        .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if isUnlocked {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
    }
}

/// Shows current tier and progress to the next tier.
private struct TierProgressView: View {
    let completedSessions: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let currentTier = Tier.current(completedSessions: completedSessions)
            let nextTierInfo = nextTier(current: currentTier)

            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                Text("Your Soul: \(currentTier.name)")
                    .font(.subheadline.weight(.medium))
            }

            if let (next, remaining) = nextTierInfo {
                Text("\(remaining) more session\(remaining == 1 ? "" : "s") to reach \(next.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("You've reached the highest tier")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func nextTier(current: Tier) -> (Tier, Int)? {
        let allTiers: [Tier] = [.spark, .glow, .shine, .radiance, .brilliance]
        guard let idx = allTiers.firstIndex(of: current), idx < allTiers.count - 1 else {
            return nil
        }
        let next = allTiers[idx + 1]
        let remaining = next.threshold - completedSessions
        return (next, remaining)
    }
}

#Preview {
    BreathTabView()
}
