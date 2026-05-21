import SwiftUI

/// Niyora Companion · iOS app that captures PPG-based stress estimates
/// (RMSSD from a 30s green-channel reading) so the Niyora Mac app can
/// show whether breathing sessions move the needle. Each capture is
/// initiated explicitly from the Mac via "Measure stress" · the app
/// stays dormant until the Mac asks.
@main
struct NiyoraCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
