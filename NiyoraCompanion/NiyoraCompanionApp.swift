import SwiftUI

/// Niyora Companion — iOS app that reads HRV from HealthKit so the Niyora
/// Mac app can show whether breathing sessions move the needle.
///
/// This build covers milestones 1-2 of the companion spec: prove we can get
/// HealthKit authorization and read HRV (SDNN) samples for a time window.
/// Sync with the Mac comes later.
@main
struct NiyoraCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
