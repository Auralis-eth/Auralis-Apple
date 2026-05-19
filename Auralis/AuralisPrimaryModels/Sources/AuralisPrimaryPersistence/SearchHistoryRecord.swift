import Foundation
import AuralisPrimaryModels
import SwiftData

@Model
public final class SearchHistoryRecord {
    #Index<SearchHistoryRecord>(
        [\.accountAddressRawValue, \.normalizedQuery],
        [\.accountAddressRawValue, \.recordedAt]
    )

    @Attribute(.unique) public var id: String
    public var accountAddressRawValue: String?
    public var normalizedQuery: String
    public var query: String
    public var recordedAt: Date

    public init(
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

    public static func scopedID(accountAddressRawValue: String?, normalizedQuery: String) -> String {
        let scope = accountAddressRawValue ?? "no-account"
        return "\(scope):\(normalizedQuery)"
    }
}
