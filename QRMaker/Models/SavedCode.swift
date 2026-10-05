import Foundation

/// A code the user has paid for. Images are regenerated from this on demand, so nothing
/// but the recipe is stored.
struct SavedCode: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var createdAt = Date()
    var title: String
    var target: QRTarget
    var style: QRStyle
    /// The exact string encoded in the code.
    var content: String
}
