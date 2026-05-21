import Foundation
import HealthKit

/// Wraps HealthKit access for the one type Niyora reads: HRV (SDNN).
///
/// Covers milestones 1-2 of the companion spec — authorization and reading
/// HRV for an arbitrary window. Deliberately single-metric: see the spec's
/// privacy stance.
@Observable
final class HealthKitManager {

    /// Whether this device can do HealthKit at all.
    enum Availability {
        case unknown
        case unavailable
        case available
    }

    /// HealthKit deliberately does NOT reveal whether *read* access was
    /// granted — only whether the permission sheet has been presented. This
    /// is an Apple privacy decision, not a bug. So we can only track whether
    /// we asked; whether data actually comes back is inferred from queries.
    enum AccessState {
        case notRequested
        case requested
        case failed
    }

    private let store = HKHealthStore()
    private let hrvType = HKQuantityType(.heartRateVariabilitySDNN)

    var availability: Availability = .unknown
    var accessState: AccessState = .notRequested
    var lastError: String?

    init() {
        availability = HKHealthStore.isHealthDataAvailable() ? .available : .unavailable
    }

    /// Presents the HealthKit permission sheet for HRV read access.
    @MainActor
    func requestAccess() async {
        guard availability == .available else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: [hrvType])
            accessState = .requested
            lastError = nil
        } catch {
            accessState = .failed
            lastError = error.localizedDescription
        }
    }

    /// Reads every HRV (SDNN) sample in `[start, end]` and returns them with a
    /// mean. An empty result is normal — do not treat it as an error.
    func readHRV(from start: Date, to end: Date) async -> HRVWindow {
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate]
        )
        let unit = HKUnit.secondUnit(with: .milli)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(returning: HRVWindow(
                        start: start, end: end, samples: [],
                        error: error.localizedDescription
                    ))
                    return
                }
                let readings: [HRVReading] = (samples as? [HKQuantitySample] ?? []).map {
                    HRVReading(date: $0.startDate, sdnnMs: $0.quantity.doubleValue(for: unit))
                }
                continuation.resume(returning: HRVWindow(
                    start: start, end: end, samples: readings, error: nil
                ))
            }
            store.execute(query)
        }
    }
}
