import Foundation
import SwiftData

@Model
final class SearchHistoryRecord {
    @Attribute(.unique) var id: String
    var accountAddressRawValue: String?
    var normalizedQuery: String
    var query: String
    var recordedAt: Date

    init(
        accountAddressRawValue: String?,
        normalizedQuery: String,
        query: String,
        recordedAt: Date = .now
    ) {
        self.id = Self.scopedID(
            accountAddressRawValue: accountAddressRawValue,
            normalizedQuery: normalizedQuery
        )
        self.accountAddressRawValue = accountAddressRawValue
        self.normalizedQuery = normalizedQuery
        self.query = query
        self.recordedAt = recordedAt
    }

    static func scopedID(accountAddressRawValue: String?, normalizedQuery: String) -> String {
        let scope = accountAddressRawValue ?? "no-account"
        return "\(scope):\(normalizedQuery)"
    }
}
