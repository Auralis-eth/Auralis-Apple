import Foundation

struct HomeRecentActivityPreviewItem: Equatable, Identifiable {
    let id: UUID
    let title: String
    let detailLine: String
    let contextLine: String
    let statusTitle: String
    let isSuccess: Bool
}
