import SwiftUI

/// Top-level tab container for the v1 standalone app. Two tabs:
///
///   1. **Breath** · guided breathing sessions, backed by `BreathTabView`
///      and the 14-technique catalog in `Techniques.swift`.
///   2. **My Soul** · session history, tier progression, and embedded
///      settings (reminders, pair status, privacy). Backed by
///      `MySoulTabView`.
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
            BreathTabView()
                .tabItem {
                    Label("Breath", systemImage: "wind")
                }

            MySoulTabView(flow: $flow)
                .tabItem {
                    Label("My Soul", systemImage: "heart.text.square")
                }
        }
    }
}

#Preview {
    RootTabView()
}
