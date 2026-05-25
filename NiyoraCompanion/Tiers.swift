import Foundation
import SwiftUI

/// Soul tier progression for My Soul. Each tier unlocks a new set of
/// breathing techniques. Cases, thresholds, and hue/saturation are the
/// canonical values from `niyora/app/src/tiers.ts` and `DESIGN.md`.
/// Must stay in sync across repos (Mac / web orb / iOS).
enum Tier: Int, CaseIterable {
    case spark = 0
    case glow = 1
    case shine = 2
    case radiance = 3
    case brilliance = 4

    /// Display name.
    var name: String {
        switch self {
        case .spark:      return "Spark"
        case .glow:       return "Glow"
        case .shine:      return "Shine"
        case .radiance:   return "Radiance"
        case .brilliance: return "Brilliance"
        }
    }

    /// Stable string id for cross-platform sync (matches tiers.ts ids).
    var id: String {
        switch self {
        case .spark:      return "spark"
        case .glow:       return "glow"
        case .shine:      return "shine"
        case .radiance:   return "radiance"
        case .brilliance: return "brilliance"
        }
    }

    /// Completed-session count needed to reach this tier (canonical).
    var threshold: Int {
        switch self {
        case .spark:      return 0
        case .glow:       return 5
        case .shine:      return 15
        case .radiance:   return 40
        case .brilliance: return 80
        }
    }

    /// Hue 0-360 for the tier's visual identity. Matches the DESIGN.md
    /// table on the Mac repo (Spark warm orange, Glow rose, Shine violet,
    /// Radiance deep blue, Brilliance cool blue).
    var hue: Double {
        switch self {
        case .spark:      return 30
        case .glow:       return 335
        case .shine:      return 280
        case .radiance:   return 230
        case .brilliance: return 210
        }
    }

    /// Saturation 0-1 for the tier's visual identity.
    var saturation: Double {
        switch self {
        case .spark:      return 0.70
        case .glow:       return 0.70
        case .shine:      return 0.65
        case .radiance:   return 0.65
        case .brilliance: return 0.60
        }
    }

    /// Brightness 0-1 for the tier's visual identity.
    var brightness: Double { 0.90 }

    /// SwiftUI Color for the tier's visual identity.
    var color: Color {
        Color(hue: hue / 360.0, saturation: saturation, brightness: brightness)
    }

    /// Resolve the current tier from a completed-session count.
    static func current(completedSessions: Int) -> Tier {
        var current: Tier = .spark
        for tier in allCases {
            if completedSessions >= tier.threshold {
                current = tier
            }
        }
        return current
    }

    /// Alias for callers that read more naturally as `forSessionCount`.
    static func forSessionCount(_ count: Int) -> Tier {
        current(completedSessions: count)
    }

    /// Sessions remaining to reach the next tier, or nil if already at
    /// the top. Caller passes the current total session count so the
    /// number returned is "X more sessions from where you are now".
    func sessionsToNext(currentCount: Int) -> Int? {
        guard let next = Tier(rawValue: rawValue + 1) else { return nil }
        return max(0, next.threshold - currentCount)
    }
}
