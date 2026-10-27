import Foundation
import AuralisOperators
import Testing

/// The allowlist that decides which web addresses the app will leave for, and what the confirmation
/// sheet says about them before it does.
struct ExternalLinkPolicyTests {
    @Test("external link policy allows approved HTTPS routes")
    func externalLinkPolicyAllowsApprovedRoutes() throws {
        let url = try #require(URL(string: "https://opensea.io/assets/ethereum/0xabc/1"))
        let result = ExternalLinkPolicy().validate(
            ExternalLinkCandidateDestination(label: "OpenSea", url: url)
        )

        switch result {
        case .success(let destination):
            #expect(destination.hostDisplay == "opensea.io")
            #expect(destination.pathDisplay == "/assets/ethereum/0xabc/1")
            #expect(destination.routeTypeDisplay == "Marketplace")
        case .failure(let failure):
            Issue.record("Expected approved route, got \(failure).")
        }
    }

    @Test("external link policy rejects insecure or unsupported destinations")
    func externalLinkPolicyRejectsUnsupportedDestinations() throws {
        let insecure = try #require(URL(string: "http://opensea.io/assets/ethereum/0xabc/1"))
        let unsupportedHost = try #require(URL(string: "https://example.com/assets/1"))

        #expect(
            ExternalLinkPolicy().validate(.init(label: "Insecure", url: insecure)) ==
                .failure(.invalidScheme("http"))
        )
        #expect(
            ExternalLinkPolicy().validate(.init(label: "Unsupported", url: unsupportedHost)) ==
                .failure(.unsupportedHost("example.com"))
        )
    }

    @Test("external link policy rejects an approved host reached over a non-web scheme")
    func externalLinkPolicyRejectsNonWebSchemes() throws {
        let url = try #require(URL(string: "javascript://opensea.io/assets/1"))

        #expect(
            ExternalLinkPolicy().validate(.init(label: "Script", url: url)) ==
                .failure(.invalidScheme("javascript"))
        )
    }

    @Test("external link policy rejects a URL with no host")
    func externalLinkPolicyRejectsMissingHost() throws {
        let url = try #require(URL(string: "https:///token/0xabc"))

        #expect(
            ExternalLinkPolicy().validate(.init(label: "Hostless", url: url)) ==
                .failure(.missingHost)
        )
    }

    @Test("external link policy rejects an unapproved path on an approved host")
    func externalLinkPolicyRejectsUnsupportedPath() throws {
        let url = try #require(URL(string: "https://etherscan.io/login"))

        #expect(
            ExternalLinkPolicy().validate(.init(label: "Login", url: url)) ==
                .failure(.unsupportedPath(host: "etherscan.io", path: "/login"))
        )
    }

    @Test("external link policy rejects a bare approved host with no route")
    func externalLinkPolicyRejectsRootPath() throws {
        let url = try #require(URL(string: "https://etherscan.io"))

        #expect(
            ExternalLinkPolicy().validate(.init(label: "Root", url: url)) ==
                .failure(.unsupportedPath(host: "etherscan.io", path: "/"))
        )
    }

    // A dot segment clears the prefix check and is displayed as an approved route while the browser
    // applies RFC 3986 normalization and loads somewhere else: `/token/../../evil` passes
    // `hasPrefix("/token/")` here and fetches `/evil`.
    //
    // `%2e%2e` is a drop-in replacement for the plain spelling — user agents decode before
    // normalizing — so the two have to stay closed together.
    //
    // The separator-bearing spellings below (`..\..\`, `%2e%2e%2f`) are defense in depth, not closed
    // bypasses: `URL` percent-encodes a literal backslash, so no user agent sees it as a separator.
    // They are pinned so the fail-closed behaviour survives a future seam that opens a URL built from
    // a string rather than from `URL`.
    @Test(
        "external link policy rejects dot-segment paths that normalize outside the allowlist",
        arguments: [
            "https://etherscan.io/token/../../evil",
            "https://etherscan.io/token/%2e%2e/%2e%2e/evil",
            #"https://etherscan.io/token/..\..\evil"#,
            "https://etherscan.io/token/%2e%2e%2f%2e%2e%2fevil",
            "https://etherscan.io/token/0xabc/..%5C..%5Cadmin",
            "https://opensea.io/assets/../login",
            "https://opensea.io/assets/%2e/%2e%2e/login",
            "https://ipfs.io/ipfs/./../admin",
            // A lone `.`, in both spellings. Every other case here also carries a `..`, so without
            // these two the current-directory branch of the check is unpinned and could be dropped
            // with the suite still green — even though normalization removes the segment, leaving the
            // approved path line describing a route that is not the one that loads.
            "https://etherscan.io/token/./0xabc",
            "https://etherscan.io/token/%2e/0xabc"
        ]
    )
    func externalLinkPolicyRejectsDotSegmentPaths(_ raw: String) throws {
        let url = try #require(URL(string: raw))
        let result = ExternalLinkPolicy().validate(.init(label: "Traversal", url: url))

        guard case .failure(let failure) = result else {
            Issue.record("Expected \(raw) to be blocked, got \(result).")
            return
        }
        guard case .unsupportedPath = failure else {
            Issue.record("Expected an unsupported-path failure for \(raw), got \(failure).")
            return
        }
    }

    @Test(
        "external link policy keeps allowing ordinary paths that merely resemble traversal",
        arguments: [
            // A segment starting with a dot, or containing dots, is not a dot *segment* — the check
            // compares whole segments, so tightening it must not start rejecting these.
            "https://etherscan.io/token/0xabc/.well-known",
            "https://etherscan.io/token/0xabc..def",
            "https://etherscan.io/token/0xabc/...",
            "https://ipfs.io/ipfs/QmHash/file.tar.gz",
            // Double-encoded: decodes once to the literal text `%2e%2e`, a segment name rather than
            // a traversal, and rejecting it would also reject any path containing `%25`.
            "https://etherscan.io/token/%252e%252e/0xabc",
            // A path parameter, not a dot segment: browsers request it verbatim, so the route shown
            // on the confirmation sheet is the route that loads.
            "https://etherscan.io/token/..;/0xabc",
            // Fullwidth dots are IDNA-mapped in hosts but never in paths, so this stays an ordinary
            // segment name end to end.
            "https://etherscan.io/token/\u{FF0E}\u{FF0E}/0xabc"
        ]
    )
    func externalLinkPolicyAllowsPathsResemblingTraversal(_ raw: String) throws {
        let url = try #require(URL(string: raw))
        let result = ExternalLinkPolicy().validate(.init(label: "Ordinary", url: url))

        guard case .success = result else {
            Issue.record("Expected \(raw) to stay approved, got \(result).")
            return
        }
    }

    // The confirmation sheet puts the host on a line of its own, so anything else the authority
    // carries is text the person approves without seeing it: `evil.example@etherscan.io` reads as a
    // bare, approved `etherscan.io`, and a port disappears from the host line entirely. Same
    // shown-route-is-not-the-loaded-route gap the dot-segment check closes for paths, so it gets the
    // same fail-closed answer.
    @Test(
        "external link policy rejects userinfo in the authority",
        arguments: [
            "https://evil.example@etherscan.io/token/0xabc",
            "https://evil.example:secret@etherscan.io/token/0xabc",
            "https://:secret@etherscan.io/token/0xabc",
            "https://@etherscan.io/token/0xabc"
        ]
    )
    func externalLinkPolicyRejectsEmbeddedCredentials(_ raw: String) throws {
        let url = try #require(URL(string: raw))

        #expect(
            ExternalLinkPolicy().validate(.init(label: "Credentialed", url: url)) ==
                .failure(.embeddedCredentials(host: "etherscan.io"))
        )
    }

    @Test(
        "external link policy rejects an explicit port",
        arguments: [8443, 443, 80]
    )
    func externalLinkPolicyRejectsExplicitPort(_ port: Int) throws {
        // 443 is in here too: nothing the app builds names a port, so there is no legitimate caller
        // to accommodate and the rule is left with no exception to reason about.
        let url = try #require(URL(string: "https://etherscan.io:\(port)/token/0xabc"))

        #expect(
            ExternalLinkPolicy().validate(.init(label: "Ported", url: url)) ==
                .failure(.unsupportedPort(host: "etherscan.io", port: port))
        )
    }

    @Test("a malformed authority is reported as malformed even when the host is not allowlisted")
    func externalLinkPolicyReportsAuthorityBeforeAllowlist() throws {
        // Ordering is part of the contract: the authority has to be well formed before asking
        // whether it is approved, and `unsupportedHost` would describe the wrong defect here.
        let url = try #require(URL(string: "https://etherscan.io@evil.example/token/0xabc"))

        #expect(
            ExternalLinkPolicy().validate(.init(label: "Both wrong", url: url)) ==
                .failure(.embeddedCredentials(host: "evil.example"))
        )
    }

    @Test("an approved route carries its query out for the confirmation surface to show")
    func externalLinkPolicyCarriesQueryDisplay() throws {
        // The allowlist approves a host and a path prefix and says nothing about the query, so the
        // route lines on the sheet understate an approved link unless the query travels beside them.
        // It is not rejected, because explorer NFT routes legitimately carry `?a=<tokenID>`.
        let queried = try #require(URL(string: "https://etherscan.io/token/0xabc?a=1"))
        let plain = try #require(URL(string: "https://etherscan.io/token/0xabc"))

        guard case .success(let withQuery) = ExternalLinkPolicy().validate(.init(label: "Queried", url: queried)),
              case .success(let withoutQuery) = ExternalLinkPolicy().validate(.init(label: "Plain", url: plain)) else {
            Issue.record("Expected both explorer routes to stay approved.")
            return
        }

        #expect(withQuery.queryDisplay == "a=1")
        #expect(withQuery.pathDisplay == "/token/0xabc")
        #expect(withoutQuery.queryDisplay == nil)
    }

    @Test("every failure names the destination it blocked")
    func externalLinkFailureMessagesNameTheDestination() {
        // These strings are the whole explanation the person gets on a blocked open, so a new case
        // that forgets to name the host would otherwise ship as a generic "something was wrong".
        #expect(ExternalLinkValidationFailure.embeddedCredentials(host: "etherscan.io").message.contains("etherscan.io"))
        #expect(ExternalLinkValidationFailure.unsupportedPort(host: "etherscan.io", port: 8443).message.contains("etherscan.io"))
        #expect(ExternalLinkValidationFailure.unsupportedPort(host: "etherscan.io", port: 8443).message.contains("8443"))
    }

    @Test("route-type selection returns only rules of the requested types")
    func externalLinkPolicyRouteTypeSelectionIsPure() {
        // The property selecting by *host* cannot provide: a host that serves two route types would
        // bring both along, re-widening a policy narrowed to one of them.
        for routeType in ExternalLinkPolicy.DefaultRouteType.allCases {
            let selected = ExternalLinkPolicy.defaultRules(for: [routeType])
            #expect(selected.isEmpty == false, "\(routeType.rawValue) selects no built-in rule.")
            #expect(
                selected.allSatisfy { $0.routeType == routeType.rawValue },
                "\(routeType.rawValue) selected a rule of another route type."
            )
        }

        #expect(ExternalLinkPolicy.defaultRules(for: []).isEmpty)
    }

    @Test("the route types partition the built-in rule set")
    func externalLinkPolicyRouteTypesPartitionTheRules() {
        // Doubles as the drift guard between `DefaultRouteType` and the route types `defaultRules`
        // actually spells: a rule naming a route the enum does not cover would drop out of the union.
        let everything = ExternalLinkPolicy.defaultRules(for: Set(ExternalLinkPolicy.DefaultRouteType.allCases))

        #expect(everything.map(\.host) == ExternalLinkPolicy.defaultRules.map(\.host))
        #expect(
            ExternalLinkPolicy.defaultRules(for: [.marketplace]).map(\.host) == ["opensea.io"]
        )
        #expect(
            ExternalLinkPolicy.defaultRules(for: [.ipfsGateway]).map(\.host) ==
                ["ipfs.io", "cloudflare-ipfs.com", "gateway.pinata.cloud"]
        )
        #expect(ExternalLinkPolicy.defaultRules(for: [.arweave]).map(\.host) == ["arweave.net"])
    }

    @Test("a route-type narrowed policy approves that route type and no other")
    func externalLinkPolicyRouteTypeScopedPolicy() throws {
        // The migration path for a surface that only ever produces one kind of link.
        let policy = try ExternalLinkPolicy(routeTypes: [.marketplace])
        let marketplace = try #require(URL(string: "https://opensea.io/assets/ethereum/0xabc/1"))
        let explorer = try #require(URL(string: "https://etherscan.io/token/0xabc"))

        guard case .success(let destination) = policy.validate(.init(label: "OpenSea", url: marketplace)) else {
            Issue.record("Expected the marketplace route to stay approved.")
            return
        }
        #expect(destination.routeTypeDisplay == "Marketplace")
        #expect(
            policy.validate(.init(label: "Explorer", url: explorer)) ==
                .failure(.unsupportedHost("etherscan.io"))
        )
    }

    @Test("narrowing to no route type is rejected rather than approving nothing")
    func externalLinkPolicyRejectsEmptyRouteTypes() {
        #expect(throws: ExternalLinkPolicy.InvalidAllowlist.empty) {
            _ = try ExternalLinkPolicy(routeTypes: [])
        }
    }

    @Test("external link policy accepts repeated hosts and resolves to the first matching rule")
    func externalLinkPolicyAcceptsRepeatedHosts() throws {
        // Two rules for one host would trap in `Dictionary(uniqueKeysWithValues:)`, so a
        // caller-supplied rule set could crash the app; `init(rules:)` groups them instead.
        let policy = ExternalLinkPolicy(rules: [
            try .init(host: "etherscan.io", allowedPathPrefixes: ["/token/"], routeType: "Token"),
            try .init(host: "etherscan.io", allowedPathPrefixes: ["/tx/"], routeType: "Transaction")
        ])

        let token = try #require(URL(string: "https://etherscan.io/token/0xabc"))
        let transaction = try #require(URL(string: "https://etherscan.io/tx/0xdef"))
        let address = try #require(URL(string: "https://etherscan.io/address/0xabc"))

        guard case .success(let tokenDestination) = policy.validate(.init(label: "Token", url: token)),
              case .success(let transactionDestination) = policy.validate(.init(label: "Tx", url: transaction)) else {
            Issue.record("Expected both rules for the repeated host to be reachable.")
            return
        }

        #expect(tokenDestination.routeTypeDisplay == "Token")
        #expect(transactionDestination.routeTypeDisplay == "Transaction")
        #expect(
            policy.validate(.init(label: "Address", url: address)) ==
                .failure(.unsupportedPath(host: "etherscan.io", path: "/address/0xabc"))
        )
    }

    @Test("an empty path prefix is rejected rather than approving the whole host")
    func externalLinkPolicyRejectsEmptyPathPrefix() {
        // `path.hasPrefix("")` is always true, so this one prefix would approve every route on an
        // allowlisted host — `/login` included — while reading as a rule scoped to something.
        #expect(throws: ExternalLinkPolicy.InvalidAllowlist.emptyPathPrefix(host: "etherscan.io")) {
            _ = try ExternalLinkPolicy.ExternalLinkRule(
                host: "etherscan.io",
                allowedPathPrefixes: ["/token/", ""],
                routeType: "Token"
            )
        }
    }

    @Test("a path prefix that cannot match a path is named rather than shipped as a dead rule")
    func externalLinkPolicyRejectsUnrootedPathPrefix() {
        // `validate` matches against `percentEncodedPath`, which always starts with `/`, so a prefix
        // that does not can never match. The payload is normalized and sorted so the caller can say
        // which entry was wrong, as with `unsupportedHosts`.
        #expect(
            throws: ExternalLinkPolicy.InvalidAllowlist.unrootedPathPrefixes(
                host: "etherscan.io",
                prefixes: ["address/", "token/"]
            )
        ) {
            _ = try ExternalLinkPolicy.ExternalLinkRule(
                host: "etherscan.io",
                allowedPathPrefixes: ["token/", "/tx/", "address/"],
                routeType: "Token"
            )
        }
    }

    @Test("a path prefix is normalized to a segment boundary instead of approving a longer name")
    func externalLinkPolicyNormalizesPathPrefixToSegmentBoundary() throws {
        // The widening spelling: `hasPrefix` is not segment-aware, so a caller writing `/token`
        // approves `/tokenzzz-phish/…` too. Appended rather than thrown because this failure mode is
        // wider than the caller intended, so tightening to the boundary it reads as is what they
        // meant. `"/"` is already at a boundary and must keep matching only the root.
        let rule = try ExternalLinkPolicy.ExternalLinkRule(
            host: "etherscan.io",
            allowedPathPrefixes: ["/token", "/tx/", "/"],
            routeType: "Token"
        )
        #expect(rule.allowedPathPrefixes == ["/token/", "/tx/", "/"])

        let policy = ExternalLinkPolicy(rules: [rule])
        let approved = try #require(URL(string: "https://etherscan.io/token/0xabc"))
        let lookalike = try #require(URL(string: "https://etherscan.io/tokenzzz-phish/0xabc"))

        guard case .success = policy.validate(.init(label: "Token", url: approved)) else {
            Issue.record("Expected the normalized prefix to still approve its own route.")
            return
        }
        #expect(
            policy.validate(.init(label: "Lookalike", url: lookalike)) ==
                .failure(.unsupportedPath(host: "etherscan.io", path: "/tokenzzz-phish/0xabc"))
        )
    }

    @Test("an approved route carries its fragment out for the confirmation surface to show")
    func externalLinkPolicyCarriesFragmentDisplay() throws {
        // Same gap as `queryDisplay`: the allowlist says nothing about the fragment, and a hash-routed
        // page picks which view it renders from it, so `#/admin` would otherwise sit inside
        // `fullURLDisplay` while the route line reads as a plain approved token route. Surfaced rather
        // than rejected, because it cannot redirect the request to another host or path.
        let fragmented = try #require(URL(string: "https://etherscan.io/token/0xabc#/admin"))
        let plain = try #require(URL(string: "https://etherscan.io/token/0xabc"))

        guard case .success(let withFragment) = ExternalLinkPolicy().validate(.init(label: "Fragmented", url: fragmented)),
              case .success(let withoutFragment) = ExternalLinkPolicy().validate(.init(label: "Plain", url: plain)) else {
            Issue.record("Expected both explorer routes to stay approved.")
            return
        }

        #expect(withFragment.fragmentDisplay == "/admin")
        #expect(withFragment.pathDisplay == "/token/0xabc")
        #expect(withoutFragment.fragmentDisplay == nil)
    }

    @Test("external link policy host uppercasing does not change the verdict")
    func externalLinkPolicyNormalizesHostCasing() throws {
        let url = try #require(URL(string: "https://ETHERSCAN.io/token/0xabc"))
        let result = ExternalLinkPolicy().validate(.init(label: "Shouty", url: url))

        guard case .success(let destination) = result else {
            Issue.record("Expected an approved route, got \(result).")
            return
        }
        #expect(destination.hostDisplay == "etherscan.io")
    }

    @Test("restricting allowed hosts blocks the hosts left out")
    func externalLinkPolicyRestrictsToAllowedHosts() throws {
        let policy = try ExternalLinkPolicy(allowedHosts: ["etherscan.io"])
        let allowed = try #require(URL(string: "https://etherscan.io/token/0xabc"))
        let excluded = try #require(URL(string: "https://opensea.io/assets/ethereum/0xabc/1"))

        guard case .success = policy.validate(.init(label: "Allowed", url: allowed)) else {
            Issue.record("Expected the retained host to stay approved.")
            return
        }
        #expect(
            policy.validate(.init(label: "Excluded", url: excluded)) ==
                .failure(.unsupportedHost("opensea.io"))
        )
    }

    @Test("restricting to a host with no built-in rule names it rather than silently dropping it")
    func externalLinkPolicyRejectsHostsWithNoDefaultRule() {
        // Restricting can only subtract: a host with no entry in `defaultRules` has no path
        // allowlist to apply, so it stays blocked while reading as a working allowlist entry. The
        // payload is part of the contract rather than a debug string — normalized and sorted, so the
        // caller can say which entry was wrong.
        #expect(
            throws: ExternalLinkPolicy.InvalidAllowlist.unsupportedHosts(["alpha.example", "zeta.example"])
        ) {
            _ = try ExternalLinkPolicy(allowedHosts: ["Zeta.example", "etherscan.io", "alpha.example"])
        }
    }

    @Test("restricting to no host at all is rejected rather than approving nothing")
    func externalLinkPolicyRejectsEmptyAllowedHosts() {
        // An empty allowlist blocks every link, which is a legitimate thing to want and an illegible
        // thing to arrive at by accident. `init(rules: [])` is the way to say it on purpose.
        #expect(throws: ExternalLinkPolicy.InvalidAllowlist.empty) {
            _ = try ExternalLinkPolicy(allowedHosts: [])
        }
    }

    @Test("an uppercase restricted host is normalized before the rule lookup")
    func externalLinkPolicyNormalizesRestrictedHostCasing() throws {
        // An uppercase host is a spelling of an approved host, not an unknown one, so it must not
        // trip `unsupportedHosts`.
        let policy = try ExternalLinkPolicy(allowedHosts: ["ETHERSCAN.IO"])
        let allowed = try #require(URL(string: "https://etherscan.io/token/0xabc"))

        guard case .success = policy.validate(.init(label: "Allowed", url: allowed)) else {
            Issue.record("Expected the uppercase spelling to resolve to the approved host.")
            return
        }
    }

    @Test("the no-argument initializer carries the full built-in rule set")
    func externalLinkPolicyDefaultInitializerCarriesEveryRule() throws {
        // `init()` is a separate, non-throwing entry point so the overwhelmingly common "use the
        // built-in allowlist" case does not have to spell `try`.
        let policy = ExternalLinkPolicy()

        for rule in ExternalLinkPolicy.defaultRules {
            let prefix = try #require(rule.allowedPathPrefixes.first)
            let url = try #require(URL(string: "https://\(rule.host)\(prefix)0xabc"))

            guard case .success(let destination) = policy.validate(.init(label: rule.host, url: url)) else {
                Issue.record("Expected \(rule.host)\(prefix) to be approved by the default policy.")
                continue
            }
            #expect(destination.routeTypeDisplay == rule.routeType)
        }
    }

    // The allowlist is the security-relevant payload of this package, so it is pinned literally
    // rather than derived. A check comparing `defaultRules` and `defaultAllowedHosts` to each other
    // cannot catch a dropped host, because both sides move together.
    private static let expectedDefaultRuleHosts: [String] = [
        "etherscan.io",
        "sepolia.etherscan.io",
        "basescan.org",
        "sepolia.basescan.org",
        "arbiscan.io",
        "sepolia.arbiscan.io",
        "nova.arbiscan.io",
        "optimistic.etherscan.io",
        "sepolia-optimism.etherscan.io",
        "polygonscan.com",
        "amoy.polygonscan.com",
        "worldscan.org",
        "sepolia.worldscan.org",
        "shapescan.xyz",
        "sepolia.shapescan.xyz",
        "explorer.inkonchain.com",
        "explorer-sepolia.inkonchain.com",
        "uniscan.xyz",
        "sepolia.uniscan.xyz",
        "soneium.blockscout.com",
        "soneium-minato.blockscout.com",
        "berascan.com",
        "explorer.zora.energy",
        "sepolia.explorer.zora.energy",
        "polynomialscan.io",
        "sepolia.polynomialscan.io",
        "opensea.io",
        "ipfs.io",
        "cloudflare-ipfs.com",
        "gateway.pinata.cloud",
        "arweave.net"
    ]

    @Test("the default allowlist covers exactly the expected hosts, in a fixed order")
    func externalLinkPolicyDefaultAllowlistIsPinned() {
        // Order is asserted, not just membership: building the explorer rules by iterating a `Set`
        // would leave which rule a host resolves to unreproducible across launches.
        #expect(ExternalLinkPolicy.defaultRules.map(\.host) == Self.expectedDefaultRuleHosts)
        #expect(ExternalLinkPolicy.defaultAllowedHosts == Set(Self.expectedDefaultRuleHosts))
    }

    @Test("every default rule carries a usable path allowlist and route type")
    func externalLinkPolicyDefaultRulesAreWellFormed() {
        // The built-in rules are constructed without going through the validating initializer, so that
        // a typo in one of the literals is a failure here rather than a trap on first use of the
        // policy. That makes this test the only guard on their prefixes — it is not redundant with the
        // initializer checks.
        for rule in ExternalLinkPolicy.defaultRules {
            #expect(!rule.allowedPathPrefixes.isEmpty, "\(rule.host) has no path allowlist, so nothing on it can ever open.")
            #expect(!rule.routeType.isEmpty, "\(rule.host) has no route type to show on the confirmation sheet.")
            #expect(rule.allowedPathPrefixes.allSatisfy { $0.hasPrefix("/") }, "\(rule.host) has a prefix that cannot match a URL path.")
            // Prefix matching is not segment-aware, so a prefix has to end at a segment boundary or
            // it approves more than it reads as: `/token` would also approve `/tokenzzz`.
            #expect(rule.allowedPathPrefixes.allSatisfy { $0.hasSuffix("/") }, "\(rule.host) has a prefix that does not end at a path segment boundary.")
            #expect(rule.host == rule.host.lowercased(), "\(rule.host) is not normalized, so host lookup will miss it.")
        }
    }
}
