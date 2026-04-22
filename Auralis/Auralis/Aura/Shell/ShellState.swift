import Foundation
import SwiftData

struct ShellState: Equatable {
    var selection: ActiveShellSelection?
    var activeAccountID: PersistentIdentifier?
    var pendingDeepLink: AppDeepLink?
    var pendingCorrelationID: String?
    var latestRefreshRequestID: UUID?
    var isRefreshingSelection = false
    var hasPresentedAuthenticatedExperience = false
    var didFinishInitialRestore = false
    var routeError: AppRouteError?
}
