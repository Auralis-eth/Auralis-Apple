import Foundation

/// Captures the shell state needed to restore selection, drive refresh, and route deferred work.
public struct ShellState: Equatable {
    public var selection: ActiveShellSelection?
    public var activeAccountID: String?
    public var pendingDeepLink: AppDeepLink?
    public var pendingCorrelationID: String?
    public var latestRefreshRequestID: UUID?
    public var isRefreshingSelection: Bool
    public var hasPresentedAuthenticatedExperience: Bool
    public var didFinishInitialRestore: Bool
    public var routeError: AppRouteError?

    public init(
        selection: ActiveShellSelection? = nil,
        activeAccountID: String? = nil,
        pendingDeepLink: AppDeepLink? = nil,
        pendingCorrelationID: String? = nil,
        latestRefreshRequestID: UUID? = nil,
        isRefreshingSelection: Bool = false,
        hasPresentedAuthenticatedExperience: Bool = false,
        didFinishInitialRestore: Bool = false,
        routeError: AppRouteError? = nil
    ) {
        self.selection = selection
        self.activeAccountID = activeAccountID
        self.pendingDeepLink = pendingDeepLink
        self.pendingCorrelationID = pendingCorrelationID
        self.latestRefreshRequestID = latestRefreshRequestID
        self.isRefreshingSelection = isRefreshingSelection
        self.hasPresentedAuthenticatedExperience = hasPresentedAuthenticatedExperience
        self.didFinishInitialRestore = didFinishInitialRestore
        self.routeError = routeError
    }
}
