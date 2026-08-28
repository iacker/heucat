import Foundation

extension ChthoniosStatus {
    /// Translated one-liner for the Sealed Profiles card.
    @MainActor var label: String {
        switch self {
        case .failed: L("profiles.checkFailed")
        case .none: L("profiles.noProfile")
        case .sealed(let names): L("profiles.sealed") + " " + names.joined(separator: ", ")
        case .unmanaged(let names): L("profiles.unmanaged") + " " + names.joined(separator: ", ")
        }
    }
}
