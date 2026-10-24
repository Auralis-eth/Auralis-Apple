import Foundation

public struct ExternalLinkPolicy: Sendable {
    public struct ExternalLinkRule: Equatable, Sendable {
        public let host: String

        /// Path prefixes a route on this host may start with.
        ///
        /// Matching is `hasPrefix` and is not segment-aware, so a prefix only approves what it looks
        /// like it approves when it ends at a segment boundary: `"/token/"` covers `/token/0xabc`,
        /// where `"/token"` would also cover `/tokenzzz`. Every stored prefix holds that invariant —
        /// ``init(host:allowedPathPrefixes:routeType:)`` appends the trailing `/` rather than trusting
        /// the caller to have written it.
        public let allowedPathPrefixes: [String]

        /// The kind of route, shown on the confirmation sheet.
        public let routeType: String

        /// Builds a rule, rejecting a path prefix that cannot mean what it reads as and normalizing
        /// one that is merely written loosely.
        ///
        /// The prefix list is the security-relevant half of a rule, and `hasPrefix` matching makes
        /// some spellings quietly wider than they look, so none is stored as given:
        ///
        /// - `""` — `path.hasPrefix("")` is always true, so an empty prefix approves *every* path on
        ///   an allowlisted host, `/login` included. Thrown rather than dropped, because a caller who
        ///   wrote it meant to approve something and a silently dropped prefix would read as a working
        ///   allowlist entry while approving nothing. ``allows(path:)`` already matches `"/"` as the
        ///   root exactly, which is the narrow thing an empty prefix is usually reaching for.
        /// - A prefix not starting with `/` — ``ExternalLinkPolicy/validate(_:)`` matches against
        ///   `percentEncodedPath`, which always does, so such a prefix can never match. It is a typo
        ///   that would otherwise ship as a rule approving nothing.
        /// - A prefix not ending with `/` — normalized by appending one, not thrown. This is the
        ///   spelling whose failure mode is *wider* than the caller intended rather than narrower, so
        ///   tightening it to the boundary it reads as is the fail-closed answer: `"/token"` becomes
        ///   `"/token/"` instead of going on to approve `/tokenzzz-phish/…`. `"/"` is already at a
        ///   boundary and is left alone.
        ///
        /// - Throws: ``InvalidAllowlist/emptyPathPrefix(host:)`` for an empty prefix, or
        ///   ``InvalidAllowlist/unrootedPathPrefixes(host:prefixes:)`` for one that cannot match a path.
        public init(host: String, allowedPathPrefixes: [String], routeType: String) throws {
            let normalizedHost = host.lowercased()

            guard !allowedPathPrefixes.contains(where: \.isEmpty) else {
                throw InvalidAllowlist.emptyPathPrefix(host: normalizedHost)
            }

            let unrooted = allowedPathPrefixes.filter { !$0.hasPrefix("/") }
            guard unrooted.isEmpty else {
                throw InvalidAllowlist.unrootedPathPrefixes(host: normalizedHost, prefixes: unrooted.sorted())
            }

            self.init(
                uncheckedHost: normalizedHost,
                allowedPathPrefixes: allowedPathPrefixes.map { $0.hasSuffix("/") ? $0 : $0 + "/" },
                routeType: routeType
            )
        }

        /// The built-in rules, whose prefixes are literals a few lines below and are pinned by
        /// `externalLinkPolicyDefaultRulesAreWellFormed`.
        ///
        /// Exists so ``ExternalLinkPolicy/defaultRules`` does not need a `try!`, which would turn a
        /// typo in one of those literals into a trap on first use of the policy rather than a test
        /// failure. Not reachable by a caller, so the checks above are the only way in from outside.
        fileprivate init(uncheckedHost host: String, allowedPathPrefixes: [String], routeType: String) {
            self.host = host.lowercased()
            self.allowedPathPrefixes = allowedPathPrefixes
            self.routeType = routeType
        }

        func allows(path: String) -> Bool {
            allowedPathPrefixes.contains { prefix in
                if prefix == "/" {
                    return path == "/"
                }
                return path.hasPrefix(prefix)
            }
        }
    }

    /// Rules indexed by host. A host maps to *all* of its rules, so one host can serve more than one
    /// route type and building a policy cannot trap on a repeated host.
    private let rulesByHost: [String: [ExternalLinkRule]]

    /// The route kinds the built-in rule set covers, so narrowing a policy to some of them is a typed
    /// choice rather than a string a caller can misspell.
    ///
    /// Only the built-in set is enumerated. ``ExternalLinkRule/routeType`` stays a `String` because it
    /// is display text, and a caller-supplied rule may name a route this enum has never heard of.
    public enum DefaultRouteType: String, CaseIterable, Sendable {
        case explorer = "Explorer"
        case marketplace = "Marketplace"
        case ipfsGateway = "IPFS gateway"
        case arweave = "Arweave"
    }

    /// Explorers share one path allowlist, so they are listed once here and turned into rules below.
    ///
    /// Ordered, not a `Set`: ``defaultRules`` is public API, and anything derived from or displayed
    /// off it needs the same order on every launch.
    private static let defaultExplorerHosts: [String] = [
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
        "sepolia.polynomialscan.io"
    ]

    public static let defaultRules: [ExternalLinkRule] = {
        let explorerPaths = ["/token/", "/address/", "/tx/"]
        return defaultExplorerHosts.map {
            ExternalLinkRule(uncheckedHost: $0, allowedPathPrefixes: explorerPaths, routeType: DefaultRouteType.explorer.rawValue)
        } + [
            ExternalLinkRule(uncheckedHost: "opensea.io", allowedPathPrefixes: ["/assets/", "/collection/"], routeType: DefaultRouteType.marketplace.rawValue),
            ExternalLinkRule(uncheckedHost: "ipfs.io", allowedPathPrefixes: ["/ipfs/"], routeType: DefaultRouteType.ipfsGateway.rawValue),
            ExternalLinkRule(uncheckedHost: "cloudflare-ipfs.com", allowedPathPrefixes: ["/ipfs/"], routeType: DefaultRouteType.ipfsGateway.rawValue),
            ExternalLinkRule(uncheckedHost: "gateway.pinata.cloud", allowedPathPrefixes: ["/ipfs/"], routeType: DefaultRouteType.ipfsGateway.rawValue),
            ExternalLinkRule(uncheckedHost: "arweave.net", allowedPathPrefixes: ["/tx/"], routeType: DefaultRouteType.arweave.rawValue)
        ]
    }()

    /// Every host ``defaultRules`` covers. Derived from the rules, so a host cannot end up on one list
    /// and not the other.
    public static let defaultAllowedHosts: Set<String> = Set(defaultRules.map(\.host))

    /// The built-in rules serving `routeTypes`.
    ///
    /// Rules, not hosts: a host may carry more than one rule, so selecting by host would hand back
    /// every route type that host serves rather than only the ones asked for.
    public static func defaultRules(for routeTypes: Set<DefaultRouteType>) -> [ExternalLinkRule] {
        let names = Set(routeTypes.map(\.rawValue))
        return defaultRules.filter { names.contains($0.routeType) }
    }

    /// What the throwing initializers reject, rather than handing back a policy that approves less
    /// than the caller asked for.
    public enum InvalidAllowlist: Error, Equatable, Sendable, CustomStringConvertible {
        /// Nothing was named, so the policy would approve no link at all. Pass an empty rule set to
        /// ``ExternalLinkPolicy/init(rules:)`` where blocking everything is the intent.
        case empty

        /// Hosts with no built-in rule, lowercased and sorted so the message is stable.
        case unsupportedHosts([String])

        /// A rule named an empty path prefix, which `hasPrefix` matches against every path — so the
        /// rule would approve the whole host rather than one route on it.
        case emptyPathPrefix(host: String)

        /// Path prefixes that do not start with `/` and so can never match a URL path, sorted so the
        /// message is stable.
        case unrootedPathPrefixes(host: String, prefixes: [String])

        public var description: String {
            switch self {
            case .empty:
                return "An external-link policy needs at least one host or route type; an empty one approves nothing."
            case .unsupportedHosts(let hosts):
                return "No built-in external-link rule for \(hosts.joined(separator: ", ")). Use ExternalLinkPolicy(rules:) to allow a host the built-in set does not cover."
            case .emptyPathPrefix(let host):
                return "An empty path prefix on \(host) would approve every route on that host, not one route. Name the route prefix, or pass \"/\" to approve only the root."
            case .unrootedPathPrefixes(let host, let prefixes):
                return "Path prefixes on \(host) have to start with \"/\", so \(prefixes.joined(separator: ", ")) can never match a route and the rule would approve nothing."
            }
        }
    }

    /// The built-in rule set — every host on ``defaultAllowedHosts``, with its own path allowlist.
    public init() {
        self.init(rules: Self.defaultRules)
    }

    /// Narrows the built-in rule set to the routes serving `routeTypes`.
    ///
    /// The narrowing to prefer when a surface produces a whole class of route. It selects rules, so a
    /// host that also serves another route type does not bring that route along with it.
    ///
    /// - Throws: ``InvalidAllowlist/empty`` if `routeTypes` is empty.
    public init(routeTypes: Set<DefaultRouteType>) throws {
        guard !routeTypes.isEmpty else {
            throw InvalidAllowlist.empty
        }
        self.init(rules: Self.defaultRules(for: routeTypes))
    }

    /// Narrows the built-in rule set to `allowedHosts`.
    ///
    /// The narrowing to prefer when a surface emits one or two named hosts: the literal is the tighter
    /// contract, and a typo in it is reported instead of dropped. Use ``init(routeTypes:)`` for a
    /// whole class of route, and ``init(rules:)`` for a host the built-in set does not cover.
    ///
    /// - Throws: ``InvalidAllowlist/unsupportedHosts(_:)`` if a host has no built-in rule. Restricting
    ///   can only subtract, so such a host has no path allowlist to apply and stays blocked while
    ///   reading as a working allowlist entry; the thrown payload names it so the caller can say which
    ///   entry was wrong. ``InvalidAllowlist/empty`` if `allowedHosts` is empty.
    public init(allowedHosts: Set<String>) throws {
        guard !allowedHosts.isEmpty else {
            throw InvalidAllowlist.empty
        }

        let normalizedHosts = Set(allowedHosts.map { $0.lowercased() })
        let unsupported = normalizedHosts.subtracting(Self.defaultAllowedHosts)
        guard unsupported.isEmpty else {
            throw InvalidAllowlist.unsupportedHosts(unsupported.sorted())
        }
        self.init(
            rules: Self.defaultRules.filter { normalizedHosts.contains($0.host) }
        )
    }

    /// Builds a policy from `rules` as given — including an empty set, which approves nothing and is
    /// the explicit way to spell a fail-closed policy.
    public init(rules: [ExternalLinkRule]) {
        self.rulesByHost = Dictionary(grouping: rules, by: \.host)
    }

    public func validate(_ candidate: ExternalLinkCandidateDestination) -> Result<ExternalLinkConfirmationDestination, ExternalLinkValidationFailure> {
        guard let components = URLComponents(url: candidate.url, resolvingAgainstBaseURL: false) else {
            return .failure(.invalidScheme(nil))
        }

        guard components.scheme?.lowercased() == "https" else {
            return .failure(.invalidScheme(components.scheme))
        }

        guard let host = components.host?.lowercased(), !host.isEmpty else {
            return .failure(.missingHost)
        }

        // The confirmation sheet shows the host on a line of its own, so anything else the authority
        // carries is text the person approves without seeing it: `evil.example@etherscan.io` reads as
        // a bare, approved `etherscan.io`, and a port does not appear on that line at all. Both are
        // checked before the allowlist lookup, because a URL has to be well formed before asking
        // whether it is approved is meaningful, and a malformed authority is the more useful verdict.
        //
        // `percentEncodedUser`/`percentEncodedPassword` rather than `user`/`password`, which decode:
        // the encoded form is the one that went over the wire.
        if components.percentEncodedUser != nil || components.percentEncodedPassword != nil {
            return .failure(.embeddedCredentials(host: host))
        }

        // Any explicit port, 443 included. Nothing the app builds names a port, so there is no
        // legitimate caller to accommodate and the rule keeps no exception to reason about later.
        if let port = components.port {
            return .failure(.unsupportedPort(host: host, port: port))
        }

        guard let rules = rulesByHost[host] else {
            return .failure(.unsupportedHost(host))
        }

        let pathDisplay = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath

        guard !Self.containsTraversalSegments(pathDisplay) else {
            return .failure(.unsupportedPath(host: host, path: pathDisplay))
        }

        guard let rule = rules.first(where: { $0.allows(path: pathDisplay) }) else {
            return .failure(.unsupportedPath(host: host, path: pathDisplay))
        }

        // Query and fragment are deliberately not allowlisted: explorer NFT routes legitimately carry
        // `?a=<tokenID>`, and neither part can change which host the request reaches or which path it
        // asks for. They are, though, the two pieces of an approved URL the sheet's host and route
        // lines do not account for, so both are carried out separately for the sheet to show rather
        // than left to be noticed inside ``ExternalLinkConfirmationDestination/fullURLDisplay``.
        //
        // The fragment earns the same treatment as the query rather than being waved through as
        // display-only: a hash-routed page picks which view it renders from it, so
        // `/token/0xabc#/admin` puts an approved `/token/0xabc` on the route line and then shows
        // something else. It is surfaced rather than rejected because, like the query, it cannot
        // redirect the request to another host or path.
        let queryDisplay = components.percentEncodedQuery
        let fragmentDisplay = components.percentEncodedFragment

        let fullURLDisplay = components.string ?? candidate.url.absoluteString
        return .success(
            ExternalLinkConfirmationDestination(
                label: candidate.label,
                url: candidate.url,
                hostDisplay: host,
                pathDisplay: pathDisplay,
                queryDisplay: queryDisplay,
                fragmentDisplay: fragmentDisplay,
                routeTypeDisplay: rule.routeType,
                fullURLDisplay: fullURLDisplay
            )
        )
    }

    /// Characters a user agent may treat as a path separator on an `https` URL. Backslash is here
    /// because the WHATWG URL Standard treats `\` as equivalent to `/` in the path of a "special"
    /// scheme, which `https` is, so a browser splits a literal backslash even though `URLComponents`
    /// does not.
    private static let pathSeparators: Set<Character> = ["/", "\\"]

    /// Whether `percentEncodedPath` contains a segment that could walk outside the route the prefix
    /// allowlist approved.
    ///
    /// Such a path is rejected outright rather than normalized and re-checked, because the URL that
    /// gets opened is the caller's original one — matching a normalized path here would approve a
    /// route the browser never loads. `URLComponents` does not apply RFC 3986 `remove_dot_segments`
    /// but user agents do, so `/token/../../evil` clears a `hasPrefix("/token/")` check, is shown to
    /// the person as an approved `/token/…` route, and then loads `/evil`.
    ///
    /// Both dot segments RFC 3986 defines are rejected, in either spelling. The encoded spellings have
    /// to be closed alongside the plain ones, because rejecting only the plain form leaves the encoded
    /// one as a drop-in replacement:
    ///
    /// - `..` / `%2e%2e` — the traversal proper. `URL` leaves the plain dots unencoded so they reach
    ///   the user agent intact, and user agents decode before they normalize, so each segment is
    ///   decoded here too.
    /// - `.` / `%2e` — the current-directory segment. It walks nowhere on its own, but
    ///   `remove_dot_segments` drops it, so the path the person approves is still not the path that
    ///   loads, and it is the padding that makes a `..` count come out wrong. Rejected on the same
    ///   fail-closed grounds rather than tolerated as harmless: no route on the allowlist needs it.
    ///
    /// A segment that *decodes* to a separator (`%2f`, `%5c`) is rejected as a separator smuggled past
    /// the split. That is defense in depth rather than a closed bypass: `URL` percent-encodes a literal
    /// backslash, so `..\..\evil` is handed to the opener as `..%5C..%5Cevil` and a user agent reads it
    /// as one ordinary segment. The rule holds the line for any future seam that opens a URL built from
    /// a string. It also rejects encoded slashes inside a segment, which no route on the allowlist —
    /// explorer token/address/tx paths, IPFS CIDs, Arweave transaction ids — needs.
    ///
    /// Deliberately *not* rejected, because none is a traversal a user agent performs:
    ///
    /// - `%252e%252e` — decodes once to the literal text `%2e%2e`, a segment name rather than a
    ///   traversal, and rejecting it would also reject any path legitimately containing `%25`.
    /// - `..;` — a path parameter. Browsers request it verbatim, so the route on the confirmation sheet
    ///   is the route that loads. Whether an origin server then normalizes it is that server's
    ///   business, not something this check can speak to.
    /// - Fullwidth `．．` (`U+FF0E`) and other Unicode dot lookalikes — IDNA-mapped in *hosts*, never in
    ///   paths, so they stay ordinary segment names end to end.
    private static func containsTraversalSegments(_ percentEncodedPath: String) -> Bool {
        percentEncodedPath
            .split(whereSeparator: { pathSeparators.contains($0) })
            .contains { segment in
                let raw = String(segment)
                let decoded = raw.removingPercentEncoding ?? raw
                if decoded == "." || decoded == ".." {
                    return true
                }
                return decoded.contains(where: { pathSeparators.contains($0) })
            }
    }
}
