import AuralisCrypto
import AuralisContext
import Foundation
import AuralisOperators
import AuralisReceipts

@MainActor
extension ReceiptEventLogger {
    func recordAppLaunch(
        accountAddress: String,
        chain: Chain,
        correlationID: String
    ) async throws -> ReceiptRecord {
        try await append(
            trigger: "app.launch",
            scope: "app",
            summary: "Launched Auralis",
            provenance: "local",
            timelineAccountAddress: accountAddress,
            timelineChainRawValue: chain.rawValue,
            rawPayload: AppLaunchReceiptPayload(
                accountAddress: accountAddress,
                chain: chain
            ).rawPayload,
            correlationID: correlationID,
            // Named, not `.system`: app launch is a specific piece of app-lifecycle work, and an
            // anonymous system actor is exactly the unattributed history P0.5-602 exists to remove.
            actorDetail: .workflow("app.lifecycle.launch"),
            authorityDetail: ReceiptAuthorityDetail(source: "policyDefault", reason: "App lifecycle work is allowed by standing policy."),
            isSuccess: true
        )
    }

    func recordContextBuilt(
        snapshot: ContextSnapshot,
        correlationID: String?
    ) async throws -> ReceiptRecord {
        try await append(
            trigger: "context.built",
            scope: "context",
            summary: "Built shell context snapshot",
            provenance: "local_cache",
            timelineAccountAddress: snapshot.scope.accountAddress.value,
            timelineChainRawValue: snapshot.scope.selectedChains.value?.first?.id,
            rawPayload: ContextBuiltReceiptPayload(snapshot: snapshot).rawPayload,
            correlationID: correlationID,
            actorDetail: .workflow("context.snapshot_builder"),
            authorityDetail: ReceiptAuthorityDetail(source: "policyDefault", reason: "Local context construction is allowed by standing policy."),
            isSuccess: true
        )
    }

    func recordExternalLinkOpened(
        label: String,
        url: URL,
        surface: String,
        accountAddress: String? = nil,
        chain: Chain? = nil,
        correlationID: String? = nil,
        provenance: ExternalLinkOpenProvenance = .userConfirmedTap
    ) async throws -> ReceiptRecord {
        try await append(
            trigger: "external_link.opened",
            scope: "navigation.external",
            summary: "Opened external link",
            provenance: provenance.rawValue,
            timelineAccountAddress: accountAddress,
            timelineChainRawValue: chain?.rawValue,
            rawPayload: ExternalLinkOpenedReceiptPayload(
                label: label,
                url: url,
                surface: surface,
                accountAddress: accountAddress,
                chain: chain,
                provenance: provenance
            ).rawPayload,
            correlationID: correlationID,
            actorDetail: provenance.receiptActorDetail,
            // Derived from the provenance, not hardcoded to `humanApproval`: an operator- or
            // plugin-initiated open has no person in the loop, and a fixed source would have the
            // receipt claim an approval nobody gave.
            authorityDetail: provenance.receiptAuthorityDetail,
            isSuccess: true
        )
    }

    func recordCopyAction(
        subject: String,
        value: String,
        surface: String,
        accountAddress: String? = nil,
        chain: Chain? = nil,
        correlationID: String? = nil
    ) async throws -> ReceiptRecord {
        try await append(
            trigger: "copy.performed",
            scope: "clipboard",
            summary: "Copied value",
            provenance: "user_provided",
            timelineAccountAddress: accountAddress,
            timelineChainRawValue: chain?.rawValue,
            rawPayload: CopyActionReceiptPayload(
                subject: subject,
                value: value,
                surface: surface,
                accountAddress: accountAddress,
                chain: chain
            ).rawPayload,
            correlationID: correlationID,
            actorDetail: .human,
            authorityDetail: ReceiptAuthorityDetail(source: "humanApproval", reason: "The person explicitly copied this value."),
            isSuccess: true
        )
    }

}

private struct AppLaunchReceiptPayload: TypedReceiptPayload {
    let accountAddress: String
    let chain: Chain

    var fields: [ReceiptPayloadField] {
        [
            .hashed("accountAddress", string: accountAddress, kind: .walletAddress),
            .public("chain", string: chain.rawValue, kind: .chain)
        ]
    }
}

private struct ContextBuiltReceiptPayload: TypedReceiptPayload {
    let snapshot: ContextSnapshot

    var fields: [ReceiptPayloadField] {
        [
            .public("schemaVersion", string: snapshot.version.rawValue, kind: .label),
            .hashed("accountAddress", string: snapshot.scope.accountAddress.value ?? "", kind: .walletAddress),
            .stringArray(
                "selectedChains",
                values: (snapshot.scope.selectedChains.value ?? []).map(\.id),
                kind: .chain
            ),
            .public("refreshState", string: snapshot.freshness.refreshState.rawValue, kind: .label),
            .bool("isStale", snapshot.freshness.isStale),
            .public("mode", string: snapshot.modeDisplay, kind: .label)
        ]
    }
}

private struct ExternalLinkOpenedReceiptPayload: TypedReceiptPayload {
    let label: String
    let url: URL
    let surface: String
    let accountAddress: String?
    let chain: Chain?
    let provenance: ExternalLinkOpenProvenance

    var fields: [ReceiptPayloadField] {
        var fields: [ReceiptPayloadField] = [
            .public("label", string: label, kind: .label),
            .public("surface", string: surface, kind: .label),
            .public("url", string: url.receiptSafeExternalLinkString, kind: .url),
            .public("provenance", string: provenance.rawValue, kind: .label)
        ]

        if let accountAddress {
            fields.append(.hashed("accountAddress", string: accountAddress, kind: .walletAddress))
        }

        if let chain {
            fields.append(.public("chain", string: chain.rawValue, kind: .chain))
        } else {
            fields.append(.null("chain"))
        }

        return fields
    }
}

private extension URL {
    var receiptSafeExternalLinkString: String {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return absoluteString
        }
        components.percentEncodedQuery = nil
        components.fragment = nil
        return components.string ?? absoluteString
    }
}

private struct CopyActionReceiptPayload: TypedReceiptPayload {
    let subject: String
    let value: String
    let surface: String
    let accountAddress: String?
    let chain: Chain?

    var fields: [ReceiptPayloadField] {
        var fields: [ReceiptPayloadField] = [
            .public("subject", string: subject, kind: .label),
            .redacted("value", string: value, kind: .copiedText),
            .public("surface", string: surface, kind: .label)
        ]

        if let accountAddress {
            fields.append(.hashed("accountAddress", string: accountAddress, kind: .walletAddress))
        }

        if let chain {
            fields.append(.public("chain", string: chain.rawValue, kind: .chain))
        }

        return fields
    }
}
