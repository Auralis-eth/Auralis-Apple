import AuralisShellCore
import Foundation
import NFTDomain
import ReceiptsCore
import Testing

extension AppDeepLink: @retroactive CustomTestStringConvertible {
    public var testDescription: String {
        switch self {
        case let .account(address, chain, destination):
            let chainPart = chain.map { String(describing: $0) } ?? "nil"
            let destinationPart = destination.map { String(describing: $0) } ?? "nil"
            return "AppDeepLink.account(address: \(address), chain: \(chainPart), destination: \(destinationPart))"
        case let .destination(destination):
            return "AppDeepLink.destination(\(destination))"
        }
    }
}

extension ShellState: @retroactive CustomTestStringConvertible {
    public var testDescription: String {
        let selectionPart = selection?.testDescription ?? "nil"
        let accountPart = activeAccountID ?? "nil"
        let deepLinkPart = pendingDeepLink?.testDescription ?? "nil"
        return """
        ShellState(selection: \(selectionPart), activeAccountID: \(accountPart), \
        pendingDeepLink: \(deepLinkPart), isRefreshing: \(isRefreshingSelection), \
        didFinishInitialRestore: \(didFinishInitialRestore), routeError: \(routeError.map { String(describing: $0) } ?? "nil"))
        """
    }
}

extension ActiveShellSelection: @retroactive CustomTestStringConvertible {
    public var testDescription: String {
        "ActiveShellSelection(address: \(address), chain: \(chain))"
    }
}

extension NFTProviderFailure: @retroactive CustomTestStringConvertible {
    public var testDescription: String {
        "NFTProviderFailure(kind: \(kind.rawValue), retryable: \(isRetryable), message: \"\(message)\")"
    }
}

extension ReceiptDraft: @retroactive CustomTestStringConvertible {
    public var testDescription: String {
        let correlation = correlationID ?? "nil"
        return """
        ReceiptDraft(scope: \(scope), trigger: \(trigger), success: \(isSuccess), \
        actor: \(actor), mode: \(mode), correlationID: \(correlation))
        """
    }
}
