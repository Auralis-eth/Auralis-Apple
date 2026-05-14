import AuralisPrimaryModels
import Foundation

/// Enumerates the intents that can mutate shell state or trigger shell side effects.
public enum ShellAction {
    case restoreFromPersistence
    case accountActivated(account: EOAccount, correlationID: String?)
    case accountSelectionRequested(address: String, correlationID: String?, chainOverride: Chain? = nil)
    case activeAccountRemovalRequested(address: String, correlationID: String?)
    case chainChangeRequested(chain: Chain, correlationID: String?)
    case refreshCurrentSelectionRequested(correlationID: String?)
    case refreshStarted(requestID: UUID, selection: ActiveShellSelection, correlationID: String?)
    case refreshFinished(requestID: UUID, selection: ActiveShellSelection)
    case deepLinkReceived(AppDeepLink)
    case attemptPendingDeepLinkReplay
    case routeErrorEncountered(AppRouteError)
    case routeErrorDismissed
    case sceneBecameActive
    case logoutRequested
    case pendingCorrelationConsumed(String?)
}
