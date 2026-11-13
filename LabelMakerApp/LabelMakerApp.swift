import SwiftUI

/// Standalone Label Maker app. Everything lives in LabelKit, which the QR Maker app also
/// includes as its Labels tab.
@main
struct LabelMakerApp: App {
    var body: some Scene {
        WindowGroup {
            LabelMakerView()
        }
    }
}
