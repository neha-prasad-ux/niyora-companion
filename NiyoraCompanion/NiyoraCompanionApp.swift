import SwiftUI
import UserNotifications

/// Niyora Companion · standalone iOS breathing app with session
/// tracking. The v1 surface is two tabs (Breath + My Soul) backed by
/// a local session store. The original PPG capture and Mac pairing
/// flow is preserved in source behind `NIYORA_V1_PPG_ENABLED` for v2.
@main
struct NiyoraCompanionApp: App {
    @AppStorage("niyora.onboarding.completed") private var onboardingCompleted = false

    init() {
        // Register the notification delegate early so cold-launch notification
        // taps are routed before the scene is created.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .fullScreenCover(
                    isPresented: Binding(
                        get: { !onboardingCompleted },
                        set: { _ in }
                    )
                ) {
                    OnboardingFlow(onComplete: { onboardingCompleted = true })
                }
        }
    }
}
