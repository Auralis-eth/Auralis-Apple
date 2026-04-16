enum ReceiptStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case success
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All Statuses"
        case .success:
            return "Successful"
        case .failed:
            return "Failed"
        }
    }
}
