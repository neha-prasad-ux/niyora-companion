import SwiftUI

/// Top-level tab container for the v1 standalone app. Two tabs:
///
///   1. **Breath** · placeholder until BreathTabView lands (sibling PR #15
///      adds it). After both PRs merge, the breath placeholder is replaced
///      by `BreathTabView()` in `RootTabView`.
///   2. **My Soul** · backed by `MySoulTabView` (introduced in this PR).
///      Owns the embedded settings (reminders, pair status, privacy).
///
/// Replaces the old `ContentView` entry point, which was built around
/// Mac pairing and PPG capture. That flow is preserved in source behind
/// the `NIYORA_V1_PPG_ENABLED` flag for v2.
///
/// `PairingFlow` is held here so MySoulTabView's pair-status section can
/// observe and act on the connection state without owning the lifecycle.
struct RootTabView: View {
    @State private var flow = PairingFlow()

    var body: some View {
        TabView {
            breathPlaceholder
                .tabItem {
                    Label("Breath", systemImage: "wind")
                }

            MySoulTabView(flow: $flow)
                .tabItem {
                    Label("My Soul", systemImage: "heart.text.square")
                }
        }
    }

    private var breathPlaceholder: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "wind")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.tint)
                Text("Breath")
                    .font(.title2.weight(.semibold))
                Text("Guided breathing sessions will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Breath")
        }
    }
}

#Preview {
    RootTabView()
}
