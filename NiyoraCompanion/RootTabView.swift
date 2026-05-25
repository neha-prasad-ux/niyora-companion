import SwiftUI

/// Top-level tab container for the v1 standalone app. Two tabs:
///
///   1. **Breath** · guided breathing sessions, backed by `BreathTabView`
///      and the 14-technique catalog in `Techniques.swift`.
///   2. **My Soul** · session history and personal stats (placeholder;
///      sibling issue niyora-companion#12 adds the list backed by
///      `LocalSessionStore`).
///
/// Replaces the old `ContentView` entry point, which was built around
/// Mac pairing and PPG capture. That flow is preserved in source behind
/// the `NIYORA_V1_PPG_ENABLED` flag for v2.
struct RootTabView: View {
    var body: some View {
        TabView {
            BreathTabView()
                .tabItem {
                    Label("Breath", systemImage: "wind")
                }

            mySoulTab
                .tabItem {
                    Label("My Soul", systemImage: "heart.text.square")
                }
        }
    }

    private var mySoulTab: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.tint)
                Text("My Soul")
                    .font(.title2.weight(.semibold))
                Text("Your session history will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("My Soul")
        }
    }
}

#Preview {
    RootTabView()
}
