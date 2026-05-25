import SwiftUI

/// Root of the v1 standalone app. No bottom tab bar: the home screen
/// IS the pre-session info view (`BreathHomeView`). My Soul is reached
/// from the top-left profile icon on the home screen.
///
/// The pairing / PPG flow from the v0 companion is preserved in source
/// behind `NIYORA_V1_PPG_ENABLED` for v2.
struct RootTabView: View {
    var body: some View {
        BreathHomeView()
            .preferredColorScheme(.dark)
    }
}

#Preview {
    RootTabView()
}
