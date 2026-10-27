import Foundation

// The gateway's non-UI surface: the service protocols its views are handed, the value types that
// travel across those protocols, and the two pure planners.
//
// Split out of `Presentation/AddressTextField.swift` (F-112) because none of it needs UIKit and all
// of it was trapped behind that file's `import UIKit`, which made the whole package unbuildable on a
// macOS host — so `swift build`/`swift test` could not reach even the parts that are platform-neutral,
// and the manifest's `.macOS("26.0")` claim was false for twenty audit rounds without anything able to
// say so. The views stay where they are, wrapped in `#if canImport(UIKit)`, which is the pattern
// `AuraUI` already uses for `AuraHaptics` and `AuraColors`.
//
// Nothing here is new and nothing changed shape; this is a move.

@MainActor
public protocol AccountActivating {
    func activateWatchAccount(
        from rawAddress: String,
        name: String?,
        source: EOAccountSource,
        correlationID: String?
    ) async throws -> AccountActivationResult
}

public struct AccountENSResolution: Equatable, Sendable {
    public let address: String
    public let ensName: String
    public let isStale: Bool

    public init(address: String, ensName: String, isStale: Bool) {
        self.address = address
        self.ensName = ensName
        self.isStale = isStale
    }
}

public enum AccountENSResolutionFailure: LocalizedError, Equatable, Sendable {
    case mappingChanged(ensName: String, cachedAddress: String, resolvedAddress: String)
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .mappingChanged:
            return "The ENS mapping changed."
        case .unavailable(let message):
            return message
        }
    }
}

@MainActor
public protocol AccountENSResolving {
    func resolveAddress(forENS ensName: String, correlationID: String) async throws -> AccountENSResolution
}

@MainActor
public protocol AccountSwitching {
    func persistPreferredChain(
        address rawAddress: String,
        chain: Chain,
        correlationID: String?
    ) async throws -> EOAccount

    func persistCurrentChain(
        address rawAddress: String,
        chain: Chain,
        correlationID: String?
    ) async throws -> EOAccount
}

@MainActor
public struct AccountsGatewayDependencies {
    public let ensResolver: any AccountENSResolving
    public let accountActivator: any AccountActivating

    public init(
        ensResolver: any AccountENSResolving,
        accountActivator: any AccountActivating
    ) {
        self.ensResolver = ensResolver
        self.accountActivator = accountActivator
    }
}

@MainActor
public enum QRScanValidationOutcome: Equatable {
    case valid
    case alert(title: String, message: String)

    public static func classify(_ scannedValue: String) -> QRScanValidationOutcome {
        let validationResult = AccountStore.validateAddressInput(scannedValue)

        switch validationResult {
        case .empty:
            return .alert(title: "Scan Failed", message: validationResult.userFacingMessage)
        case .unsupportedENS:
            return .alert(title: "ENS Not Supported Yet", message: validationResult.userFacingMessage)
        case .invalidFormat:
            return .alert(title: "Scan Failed", message: validationResult.userFacingMessage)
        case .valid:
            return .valid
        }
    }
}

public struct AccountSwitcherSelection: Equatable, Sendable {
    public let address: String
    public let chain: Chain

    public init(address: String, chain: Chain) {
        self.address = address
        self.chain = chain
    }
}

public enum ChainScopeChangeKind: Equatable, Sendable {
    case preferred
    case current
}

public struct ChainScopeChangePlan: Equatable {
    public let kind: ChainScopeChangeKind
    public let to: Chain
    public let shouldApply: Bool
    public let shouldRefreshActiveScope: Bool
    public let event: AccountEvent?

    public init(
        kind: ChainScopeChangeKind,
        to: Chain,
        shouldApply: Bool,
        shouldRefreshActiveScope: Bool,
        event: AccountEvent?
    ) {
        self.kind = kind
        self.to = to
        self.shouldApply = shouldApply
        self.shouldRefreshActiveScope = shouldRefreshActiveScope
        self.event = event
    }
}

public struct ChainScopeChangePlanner: Sendable {
    public init() {}

    public func planPreferredChange(address: String, from: Chain, to: Chain) -> ChainScopeChangePlan {
        makePlan(kind: .preferred, address: address, from: from, to: to)
    }

    public func planCurrentChange(address: String, from: Chain, to: Chain) -> ChainScopeChangePlan {
        makePlan(kind: .current, address: address, from: from, to: to)
    }

    private func makePlan(
        kind: ChainScopeChangeKind,
        address: String,
        from: Chain,
        to: Chain
    ) -> ChainScopeChangePlan {
        guard from != to else {
            return ChainScopeChangePlan(
                kind: kind,
                to: to,
                shouldApply: false,
                shouldRefreshActiveScope: false,
                event: nil
            )
        }

        let event: AccountEvent = switch kind {
        case .preferred:
            .preferredChainChanged(address: address, from: from, to: to)
        case .current:
            .currentChainChanged(address: address, from: from, to: to)
        }

        return ChainScopeChangePlan(
            kind: kind,
            to: to,
            shouldApply: true,
            shouldRefreshActiveScope: kind == .current,
            event: event
        )
    }
}
