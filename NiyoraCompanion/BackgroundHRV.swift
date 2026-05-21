import HealthKit
import UIKit

/// Lights up HealthKit Background Delivery for HRV so iOS wakes the
/// Companion app silently each time the Apple Watch records a new SDNN
/// sample. On wake we reconnect to the paired Mac and let `PairingFlow`
/// drain any queued windows + compute and send their HRV deltas, all
/// within the ~30s wake budget Apple gives us.
///
/// Once the user has paired with a Mac and granted HealthKit access, the
/// Companion no longer needs to be opened by hand · the wakes drive the
/// loop in the background. The user only opens it again for debug,
/// re-pairing a new iPhone, or unpairing.
@MainActor
final class BackgroundHRV {

    static let shared = BackgroundHRV()

    private let store = HKHealthStore()
    private let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
    private var observer: HKObserverQuery?
    private var started = false

    private init() {}

    /// Called once on app launch (foreground or background). Idempotent.
    func start() {
        guard !started else { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        started = true

        // Enable background delivery. iOS wakes us when the Watch (or any
        // source) writes a new HRV sample to HealthKit. `.immediate` is
        // fine for HRV because the Watch only logs it every few minutes
        // on its own schedule · we are not polling, we are reacting.
        store.enableBackgroundDelivery(for: hrvType, frequency: .immediate) { _, _ in
            // Failure here is non-fatal · the foreground reconnect path
            // still works, the user just has to open the app to drain.
        }

        let q = HKObserverQuery(sampleType: hrvType, predicate: nil) { [weak self] _, completion, _ in
            Task { @MainActor in
                await self?.handleWake()
                completion()
            }
        }
        store.execute(q)
        observer = q
    }

    /// Drive a short reconnect → drain → send cycle. Bounded so we always
    /// return well inside Apple's wake budget.
    private func handleWake() async {
        // If the user has the app foregrounded right now the existing
        // PairingFlow is already maintaining the connection. Spawning a
        // second one would race for the same client_id slot on the Mac.
        guard UIApplication.shared.applicationState != .active else { return }

        guard let known = KnownServerStore.all().first else { return }

        let flow = PairingFlow()
        flow.reconnect(to: known)

        // Stop early when no window activity for 3s in a row · the queue
        // is drained. Hard cap at 25s so iOS never times us out.
        let deadline = Date().addingTimeInterval(25)
        var lastActivityAt = Date()
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if case .receivingWindow = flow.state {
                lastActivityAt = Date()
            }
            if Date().timeIntervalSince(lastActivityAt) > 3 {
                break
            }
        }
        flow.disconnect()
    }
}
