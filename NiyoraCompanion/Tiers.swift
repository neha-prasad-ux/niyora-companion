import Foundation
import SwiftUI

/// Soul tier progression based on session count. Spark is the starting
/// tier; each subsequent tier unlocks at a higher session count. Ported
/// from niyora/app/src/tiers.ts.
enum Tier: Int, CaseIterable {
    case spark = 0
    case glow = 1
    case radiance = 2
    case luminance = 3
    case brilliance = 4

    var name: String {
        switch self {
        case .spark: return "Spark"
        case .glow: return "Glow"
        case .radiance: return "Radiance"
        case .luminance: return "Luminance"
        case .brilliance: return "Brilliance"
        }
    }

    /// Session count threshold to reach this tier.
    var threshold: Int {
        switch self {
        case .spark: return 0
        case .glow: return 7
        case .radiance: return 21
        case .luminance: return 50
        case .brilliance: return 100
        }
    }

    /// Hue value (0-360) for visual identity. Each tier shifts the primary
    /// color slightly to give a distinct feel while maintaining continuity.
    var hue: Double {
        switch self {
        case .spark: return 30      // Warm orange
        case .glow: return 45       // Golden yellow
        case .radiance: return 60   // Yellow-green
        case .luminance: return 200 // Blue
        case .brilliance: return 280 // Purple
        }
    }

    /// Saturation for the tier's visual identity (0-1).
    var saturation: Double {
        switch self {
        case .spark: return 0.7
        case .glow: return 0.75
        case .radiance: return 0.8
        case .luminance: return 0.85
        case .brilliance: return 0.9
        }
    }

    /// Brightness for the tier's visual identity (0-1).
    var brightness: Double {
        return 0.9
    }

    /// SwiftUI Color for this tier.
    var color: Color {
        Color(hue: hue / 360.0, saturation: saturation, brightness: brightness)
    }

    /// Determine the current tier based on total session count.
    static func forSessionCount(_ count: Int) -> Tier {
        // Walk backwards through tiers to find the highest one whose
        // threshold is met.
        for tier in allCases.reversed() {
            if count >= tier.threshold {
                return tier
            }
        }
        return .spark
    }

    /// Sessions remaining until the next tier, or nil if already at max.
    func sessionsToNext(currentCount: Int) -> Int? {
        guard let nextTier = Tier(rawValue: self.rawValue + 1) else {
            return nil
        }
        return nextTier.threshold - currentCount
    }
}
