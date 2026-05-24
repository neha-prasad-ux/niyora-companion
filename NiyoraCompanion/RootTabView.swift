import SwiftUI

/// Top-level tab container for the v1 standalone app. Two tabs:
///
///   1. **Breath** — guided breathing sessions (placeholder for now;
///      sibling issue fills in the technique picker and animations).
///   2. **My Soul** — session history and personal stats (placeholder;
///      sibling issue adds the list backed by LocalSessionStore).
///
/// Replaces the old `ContentView` entry point, which was built around
/// Mac pairing and PPG capture. That flow is preserved behind the
/// `NIYORA_V1_PPG_ENABLED` flag for v2.
struct RootTabView: View {
    var body: some View {
        TabView {
            breathTab
            mySoulTab
        }
    }

    private var breathTab: some View {
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
        .tabItem {
            Label("Breath", systemImage: "wind")
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
        .tabItem {
            Label("My Soul", systemImage: "heart.text.square")
        }
    }
}

#Preview {
    RootTabView()
}
