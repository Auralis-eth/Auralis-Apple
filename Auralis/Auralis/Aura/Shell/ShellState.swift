import Foundation
import SwiftData

/// Captures the shell state needed to restore selection, drive refresh, and route deferred work.
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
