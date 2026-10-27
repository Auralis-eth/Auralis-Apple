import AuralisShellCore
import Foundation
import NFTDomain
import AuralisReceipts
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
        // `correlationID` **is** optional, so this coalesces rather than interpolating directly.
        //
        // Round 8 removed a `?? "nil"` here on the stated grounds that "the initializer substitutes
        // a fresh UUID for a nil or empty one — so the `?? "nil"` this used to carry was dead the
        // moment the column became required". That premise no longer holds, and was deliberately
        // reversed: `ReceiptDraft.correlationID` is `String?` again, because substituting a UUID
        // would make the receipt *assert* membership in a workflow run no session, worklog or caller
        // holds — and, since the value is folded into the chain hash, assert it unfalsifiably. See
        // the doc comment on that property.
        //
        // Interpolating the optional directly is not merely a warning: it prints
        // `Optional("flow-1")` or `nil` via the debug description, so every failure message
        // involving a draft carried the wrapper instead of the value.
        let correlationPart = correlationID ?? "nil"
        return """
        ReceiptDraft(scope: \(scope), trigger: \(trigger), success: \(isSuccess), \
        actor: \(actor), mode: \(mode), correlationID: \(correlationPart))
        """
    }
}
