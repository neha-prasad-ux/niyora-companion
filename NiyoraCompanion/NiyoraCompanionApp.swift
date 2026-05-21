import SwiftUI
import UIKit

/// Niyora Companion · iOS app that reads HRV from HealthKit so the
/// Niyora Mac app can show whether breathing sessions move the needle.
@main
struct NiyoraCompanionApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// We need an AppDelegate to start HealthKit Background Delivery as
/// early as possible · in particular on background launches when the OS
/// wakes us to deliver a new HRV sample. The SwiftUI App init runs in
/// both foreground and background launches, but doing the wake-up
/// plumbing from the delegate keeps things conventional and ensures
/// the observer query is registered before the system fires it.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        Task { @MainActor in
            BackgroundHRV.shared.start()
        }
        return true
    }
}
