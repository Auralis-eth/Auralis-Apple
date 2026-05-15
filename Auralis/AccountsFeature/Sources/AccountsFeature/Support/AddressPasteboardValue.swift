import Foundation

public struct AddressPasteboardValue: Equatable, Sendable {
    public let address: String

    public init?(rawValue: String?) {
        guard let trimmed = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else {
            return nil
        }

        self.address = trimmed
    }
}
