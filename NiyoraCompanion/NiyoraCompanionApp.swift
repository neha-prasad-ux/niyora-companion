import SwiftUI

/// Niyora Companion · standalone iOS breathing app with session
/// tracking. The v1 surface is two tabs (Breath + My Soul) backed by
/// a local session store. The original PPG capture and Mac pairing
/// flow is preserved behind `NIYORA_V1_PPG_ENABLED` for v2.
@main
struct NiyoraCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
    }
}
