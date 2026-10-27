import Foundation
@testable import OperatorsFeature
import Testing

/// A real EIP-55 mixed-case mainnet address, so case folding is exercised against a value that
/// actually carries checksum casing rather than a flat lowercase stub.
private let vitalik = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"

@Suite("Watch targets")
struct WatchTargetTests {
    /// `id` is the `(chain, address)` pair, case-folded on both halves — the identity the whole
    /// feature keys on. `OperatorArtifactComposer.matches` and `ReceiptBackedOperatorDataSource`
    /// both narrow activity to this pair, so the two spellings a user and a receipt payload use for
    /// the same account have to resolve to one target.
    @Test
    func idFoldsCaseOnBothTheChainAndTheAddress() {
        let mixed = WatchTarget(chain: "Ethereum", address: "0xD8DA6BF26964AF9D7EED9E03E53415D37AA96045")
        let lower = WatchTarget(chain: "ethereum", address: "0xd8da6bf26964af9d7eed9e03e53415d37aa96045")
        #expect(mixed.id == lower.id)
        // The chain half resolves to a canonical `Chain` raw value rather than staying as whatever
        // the caller typed — `"ethereum"` is an alias, `"eth-mainnet"` is the identity. That is what
        // makes this key agree with `chain.inScope`; see `WatchTarget.chainKey`.
        #expect(mixed.id == "eth-mainnet:0xd8da6bf26964af9d7eed9e03e53415d37aa96045")

        // Same address, different chain is a *different* target. An address is only unique within a
        // chain, which is why the id carries both.
        #expect(WatchTarget(chain: "base", address: mixed.address).id != mixed.id)
    }

    /// The address half of the key, which lagged the chain half.
    ///
    /// Fails against a bare `address.lowercased()`: whitespace and the `0x` prefix both produced a
    /// second, distinct target for one account. The padded form then matched nothing — `matches`
    /// compared with `caseInsensitiveCompare`, which compares lengths — so the account rendered
    /// under two headings, one of them reporting "_No recent observed activity._" for an account
    /// that had some. `AddressFormatCheck` does not catch either spelling: `AuralisEthereumAddress`
    /// trims, and it accepts an unprefixed 40-hex body as the same address.
    @Test
    func addressKeyFoldsWhitespaceAndThePrefixSoOneAccountIsOneTarget() {
        let canonical = WatchTarget(
            chain: "ethereum",
            address: "0xd8da6bf26964af9d7eed9e03e53415d37aa96045"
        )
        let padded = WatchTarget(
            chain: "ethereum",
            address: "  0xD8dA6BF26964Af9D7eEd9e03E53415D37aA96045  "
        )
        let unprefixed = WatchTarget(
            chain: "ethereum",
            address: "d8da6bf26964af9d7eed9e03e53415d37aa96045"
        )

        #expect(padded.id == canonical.id)
        #expect(unprefixed.id == canonical.id)
        // The key emits the one spelling `ToolSchemaField.Kind.address` accepts, so a value derived
        // from it cannot fail output-schema validation after the artifact has been persisted.
        #expect(WatchTarget.normalizedAddress(unprefixed.address).hasPrefix("0x"))
        // ...and preserves case while doing it, because the mixed case in a checksummed address is
        // the EIP-55 integrity check and `preparedActionAddress` is read by a human before approval.
        #expect(
            WatchTarget.normalizedAddress("  0xD8dA6BF26964Af9D7eEd9e03E53415D37aA96045  ")
                == "0xD8dA6BF26964Af9D7eEd9e03E53415D37aA96045"
        )
        // A value that is not an address is left alone rather than collapsed, so unrecognized input
        // still compares consistently with itself.
        #expect(WatchTarget.addressKey(" Not An Address ") == "not an address")
    }

    /// The normalizer must not *manufacture* an address shape out of characters the validating
    /// layers refuse.
    ///
    /// `Character.isHexDigit` is true for the fullwidth digit forms (`０`–`９`) and other Unicode
    /// digit variants, so a 40-character body made of them satisfied the length-and-hex branch and
    /// got a `0x` prefix prepended. That value is what `composeWatch` and `composePreparedAction`
    /// put into `PreparedAction.address` and the executor puts into the `preparedActionAddress`
    /// output field — which `ToolSchemaField.Kind.address` validates ASCII-strictly, *after* the
    /// artifact has been persisted. `normalizedAddress`'s own documentation promises this cannot
    /// happen; it only holds with the ASCII restriction. AuralisRuntime records the same permissive
    /// test reaching `draftTransaction` before `AuralisEthereumAddress` was tightened.
    @Test(arguments: [
        // Forty fullwidth digits: `isHexDigit` says yes, every validating layer says no.
        String(repeating: "０", count: 40),
        // Mixed ASCII and Arabic-Indic digits, still forty characters.
        String(repeating: "d", count: 39) + "١"
    ])
    func nonASCIIHexDigitsAreNeverCoercedIntoAnAddressShape(body: String) {
        let normalized = WatchTarget.normalizedAddress(body)
        // Left alone, not dressed up as an address.
        #expect(normalized == body)
        #expect(normalized.hasPrefix("0x") == false)
        // And an already-prefixed one keeps whatever it was rather than being re-blessed.
        #expect(WatchTarget.normalizedAddress("0x" + body) == "0x" + body)
    }

    /// Label, then ENS, then a truncated address — and an empty string counts as absent at each
    /// rung, so a target carrying `label: ""` falls through to the ENS name instead of rendering a
    /// blank heading in the watch report.
    @Test(arguments: [
        (WatchTarget(chain: "ethereum", address: vitalik, ens: "vitalik.eth", label: "Treasury"), "Treasury"),
        (WatchTarget(chain: "ethereum", address: vitalik, ens: "vitalik.eth"), "vitalik.eth"),
        (WatchTarget(chain: "ethereum", address: vitalik, ens: "vitalik.eth", label: ""), "vitalik.eth"),
        (WatchTarget(chain: "ethereum", address: vitalik), "0xd8dA…6045"),
        (WatchTarget(chain: "ethereum", address: vitalik, ens: "", label: ""), "0xd8dA…6045")
    ])
    func displayNamePrefersLabelThenENSThenShortAddress(target: WatchTarget, expected: String) {
        #expect(target.displayName == expected)
    }

    /// The address rung truncates the *normalized* spelling, so an unlabelled target names its
    /// account the same way the prepared packet does.
    ///
    /// `displayName` was the last site still rendering the caller's raw spelling after the body and
    /// the packet were moved onto one. It is the `## heading` of a watch section, the
    /// `PreparedAction.title`, the artifact *title* of a prepared packet, and the watchlist row in
    /// Mission Control — each of them sitting beside a normalized `preparedActionAddress`. Both
    /// spellings below are ones `AddressFormatCheck` admits, so they reach a governed run: the bare
    /// 40-hex form read `d8dA6B…6045` above a packet for `0xd8dA6BF…6045`, and the padded form spent
    /// its elision budget on whitespace (`  0xd8…45  `), showing two fewer identifying characters
    /// than the short form exists to carry.
    @Test(arguments: [
        "d8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
        "  0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045  ",
        "0Xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
    ])
    func displayNameShortensTheSameSpellingThePreparedPacketCarries(spelling: String) {
        let target = WatchTarget(chain: "ethereum", address: spelling)
        #expect(target.displayName == "0xd8dA…6045")
        // Derived from the value that crosses the boundary, not from the raw one — and still
        // case-preserving, so the EIP-55 signal in the retained characters survives.
        #expect(
            target.displayName
                == WatchTarget.shortAddress(WatchTarget.normalizedAddress(target.address))
        )
    }

    /// A value `normalizedAddress` declines to coerce still cannot end a line the composer owns.
    ///
    /// The last raw interpolation in the feature. `flattenedChain` was added because the chain half
    /// of a target is interpolated into lines `OperatorArtifactComposer` writes and signs its name
    /// to; the address half is interpolated into the same lines — `` `<address>` ``,
    /// `- Address: `<address>``, and the restored `` - `<address>` on <chain> `` — and came back
    /// from here with only its *ends* trimmed whenever it was not a recognized 40-hex body. An
    /// interior break therefore split a composer-owned line and wrote an unowned one into a durable,
    /// receipted artifact, which is the same defect, on the value sitting beside the one that was
    /// fixed.
    ///
    /// The recognized spelling is unaffected — pinned below, because flattening a value that is
    /// about to become `preparedActionAddress` must not perturb it by so much as a character.
    @Test(arguments: [
        "0xAAAA\n## Target\n- Address: `0x000000000000000000000000000000000000bEEF`",
        "not\u{2028}an\u{2028}address",
        "0x\u{0000}0001"
    ])
    func anUnrecognizedAddressIsFlattenedSoItCannotEndAComposerOwnedLine(spelling: String) {
        let normalized = WatchTarget.normalizedAddress(spelling)
        #expect(normalized.contains("\n") == false)
        #expect(normalized.contains("\u{2028}") == false)
        #expect(normalized.components(separatedBy: .newlines).count == 1)
        // Still visibly the caller's value rather than blanked, so an unrecognized target stays
        // recognizably unrecognized.
        #expect(normalized.isEmpty == false)
    }

    /// …and a well-formed address is returned character for character, because this value becomes
    /// `preparedActionAddress` and its EIP-55 case is an integrity check.
    @Test(arguments: [
        "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
        "d8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
        "  0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045  ",
        "0Xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
    ])
    func aRecognizedAddressIsUnchangedByTheFlattening(spelling: String) {
        #expect(WatchTarget.normalizedAddress(spelling) == "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045")
    }

    /// A value `normalizedAddress` refuses to coerce is still shortened as-is rather than hidden, so
    /// an unrecognized target is visibly unrecognized instead of silently renamed.
    @Test
    func displayNameLeavesANonAddressAlone() {
        #expect(WatchTarget(chain: "ethereum", address: "not-an-address-value").displayName == "not-an…alue")
    }

    /// Truncation only kicks in above 12 characters, so a short identifier is shown whole rather
    /// than replaced by an abbreviation no shorter than the original.
    @Test(arguments: [
        (vitalik, "0xd8dA…6045"),
        ("0x1234567890", "0x1234567890"),
        ("0x12345678901", "0x1234…8901"),
        ("short", "short"),
        ("", "")
    ])
    func shortAddressTruncatesOnlyWhenItSaves(address: String, expected: String) {
        #expect(WatchTarget.shortAddress(address) == expected)
    }

    /// `label` is the one scope field no deterministic check validates, and it outranks the one that
    /// is validated.
    ///
    /// `chain` goes through `chain.inScope`, `address` through `address.format`, and `ens` through
    /// `ens.format` — which exists, per ``OperatorCatalog``'s own note, because `displayName` prefers
    /// the ENS name and "an unchallenged homoglyph became the title of an approval". `label` sits
    /// *above* `ens` on that ladder, is decoded straight out of the untrusted `watchlist` JSON, and
    /// nothing anywhere looks at it. So it arrives unbounded and may contain line breaks, and
    /// `displayName` is interpolated into Markdown *headings* the composer owns — `## <name> —
    /// <chain>`, `# Prepared Action Packet: <name>` — as well as into the artifact title and the
    /// `ToolCallArtifact.summary` that becomes the receipt's.
    ///
    /// Flattening is the structural half of the answer: a Markdown heading only starts at the
    /// beginning of a line, so a name that cannot contain a line break cannot forge a block.
    @Test
    func displayNameIsASingleBoundedLineEvenFromAHostileLabel() {
        let forged = WatchTarget(
            chain: "ethereum",
            address: vitalik,
            ens: "treasury.eth",
            label: "Treasury\n## Target\n- Address: `0x000000000000000000000000000000000000bEEF`"
        )

        #expect(!forged.displayName.contains("\n"))
        #expect(!forged.displayName.contains("\r"))
        // The text survives — what is removed is its ability to be structure.
        #expect(forged.displayName.hasPrefix("Treasury "))
        #expect(forged.displayName.count <= WatchTarget.maximumDisplayNameLength)

        // U+2028 LINE SEPARATOR is a line break to a Markdown renderer and is not in
        // `CharacterSet.controlCharacters`, so flattening has to split on `.newlines` too.
        let separated = WatchTarget(chain: "ethereum", address: vitalik, label: "A\u{2028}## Target")
        #expect(separated.displayName == "A ## Target")

        // Unbounded in, bounded out: the label reaches `Artifact.title` and the receipt summary.
        let long = WatchTarget(chain: "ethereum", address: vitalik, label: String(repeating: "x", count: 5_000))
        #expect(long.displayName.count <= WatchTarget.maximumDisplayNameLength)
    }

    /// A label that is only whitespace or only control characters names nothing, so the ladder keeps
    /// descending instead of rendering `## — ethereum` and `Prepared Action Packet: `.
    @Test(arguments: ["", "   ", "\n\t", "\u{0000}\u{0007}"])
    func aLabelThatNamesNothingFallsThroughToTheNextRung(label: String) {
        let target = WatchTarget(chain: "ethereum", address: vitalik, ens: "treasury.eth", label: label)
        #expect(target.displayName == "treasury.eth")
        #expect(WatchTarget(chain: "ethereum", address: vitalik, label: label).displayName == "0xd8dA…6045")
    }
}

@Suite("Operator request parameters")
struct OperatorRequestTests {
    /// `toParameters()` is how a request reaches the receipt, and `init(parameters:)` is how the
    /// receipt is read back — the artifact is only "reproducible from its receipt" if the pair is
    /// lossless. The watchlist in particular survives as JSON, so more than its primary target and
    /// every target's `ens`/`label` come back.
    @Test(arguments: [
        OperatorRequest(query: "gas usage"),
        OperatorRequest(identityID: "did:example:123"),
        OperatorRequest(query: "gas usage", identityID: "did:example:123", playbookID: "research.brief"),
        OperatorRequest(watchlist: [
            WatchTarget(chain: "ethereum", address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045", ens: "vitalik.eth", label: "Treasury")
        ]),
        OperatorRequest(watchlist: [
            WatchTarget(chain: "ethereum", address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045", ens: "vitalik.eth"),
            WatchTarget(chain: "base", address: "0x0000000000000000000000000000000000000001", label: "Ops")
        ]),
        OperatorRequest(
            query: "unresolved approvals",
            watchlist: [WatchTarget(chain: "base", address: "0x0000000000000000000000000000000000000001")],
            identityID: "did:example:123",
            playbookID: "watch.daily"
        )
    ])
    func parametersRoundTripLosslessly(request: OperatorRequest) {
        #expect(OperatorRequest(parameters: request.toParameters()) == request)
    }

    /// The primary target is additionally flattened onto `chain`/`address`/`ens` because those are
    /// the names the deterministic address, chain-scope, and ENS-format checks read. A watchlist
    /// that only travelled as JSON would pass through `address.format` and `chain.inScope`
    /// unexamined.
    @Test
    func primaryTargetIsFlattenedOntoTheCheckedParameterNames() {
        let parameters = OperatorRequest(watchlist: [
            WatchTarget(chain: "base", address: "0x0000000000000000000000000000000000000001", ens: "ops.eth"),
            WatchTarget(chain: "ethereum", address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045")
        ]).toParameters()

        #expect(parameters["chain"] == "base")
        #expect(parameters["address"] == "0x0000000000000000000000000000000000000001")
        #expect(parameters["ens"] == "ops.eth")
        #expect(parameters["watchlist"] != nil)
    }

    /// Blank and whitespace-only scope values are dropped rather than emitted, so a schema field
    /// declared `.string` (which rejects an empty value) is never handed `" "`, and no check is
    /// asked to validate whitespace.
    @Test(arguments: ["", "   ", "\n\t"])
    func blankScopeValuesAreOmittedEntirely(blank: String) {
        let parameters = OperatorRequest(
            query: blank,
            identityID: blank,
            playbookID: blank
        ).toParameters()
        #expect(parameters.isEmpty)
    }

    @Test
    func surroundingWhitespaceIsTrimmedFromScopeValues() {
        let parameters = OperatorRequest(
            query: "  gas usage  ",
            identityID: " did:example:123\n",
            playbookID: "\tresearch.brief "
        ).toParameters()
        #expect(parameters["query"] == "gas usage")
        #expect(parameters["identityID"] == "did:example:123")
        #expect(parameters["playbookID"] == "research.brief")
    }

    /// A proposal carrying only the flattened `address`/`chain`/`ens` — a hand-built proposal, or a
    /// receipt written before the watchlist field existed — still rebuilds a usable target.
    @Test
    func anAddressOnlyProposalRebuildsASingleTarget() {
        let request = OperatorRequest(parameters: [
            "chain": "base",
            "address": "0x0000000000000000000000000000000000000001",
            "ens": "ops.eth"
        ])
        #expect(request.watchlist == [
            WatchTarget(chain: "base", address: "0x0000000000000000000000000000000000000001", ens: "ops.eth")
        ])
    }

    /// An address with no chain names **no** target, rather than being defaulted onto Ethereum
    /// mainnet.
    ///
    /// Replaces `anAddressWithNoChainDefaultsToEthereum`, whose assertions pinned a real defect and
    /// whose stated justification was false on both halves. It claimed the invented chain was safe
    /// because "`chain.inScope` still gets to judge the result": `ChainScopeCheck` reads
    /// `proposal.parameters["chain"]`, so on a proposal that carries none it returns `passed: true`
    /// with "no chain to check" and never sees the value, which is invented *after* it runs. It then
    /// claimed a watch cannot reach here without a chain — true, its input schema requires one, but
    /// Research Brief and Identity Review declare no chain field and their schemas are
    /// `allowsAdditionalFields: true`, so `{query, address}` clears schema validation and
    /// `chain.inScope` alike and then ran against Ethereum mainnet: a live JSON-RPC read through
    /// `LiveOnChainOperatorDataSource` and a durable receipted artifact naming a chain nobody asked
    /// for, outside any `allowedChains` the policy configured.
    @Test(arguments: [nil, "", "   "] as [String?])
    func anAddressWithNoNamedChainNamesNoTargetRatherThanAssumingOne(chain: String?) {
        var parameters = ["address": "0x0000000000000000000000000000000000000001"]
        if let chain { parameters["chain"] = chain }

        let request = OperatorRequest(parameters: parameters)

        #expect(request.watchlist.isEmpty)
        // Specifically: no fabricated mainnet scope.
        #expect(request.watchlist.map(\.chain).contains("ethereum") == false)
    }

    /// The mirror case: a chain with no address is not a target either, so neither half can stand
    /// in for a whole one. This is the shape `WatchlistEntry` already enforces on the JSON path by
    /// declaring both fields non-optional.
    @Test
    func aChainWithNoAddressNamesNoTarget() {
        #expect(OperatorRequest(parameters: ["chain": "base"]).watchlist.isEmpty)
    }

    /// Unreadable watchlist JSON yields *no* scope, even when flattened parameters sit beside it.
    /// Falling back there would disagree with AuralisRuntime's `CheckTargets.decode`, which treats the
    /// mere presence of the `watchlist` key as the whole scope and fails the proposal when it will
    /// not parse. An empty list is the one answer that cannot be a target the checks never saw.
    @Test(arguments: [
        "0x0000000000000000000000000000000000000001",
        nil
    ] as [String?])
    func malformedWatchlistJSONYieldsNoScopeRatherThanTheFlattenedTarget(address: String?) {
        var parameters = ["watchlist": "{not json"]
        if let address {
            parameters["address"] = address
            parameters["chain"] = "base"
        }
        #expect(OperatorRequest(parameters: parameters).watchlist.isEmpty)
    }

    /// The divergence that made this a real defect rather than a style point: a watchlist blob the
    /// *checks'* decoder accepts but `WatchTarget` does not. `WatchlistEntry` has no `label` key, so
    /// it ignores the integer `5` and validates one well-formed Ethereum target; `WatchTarget.label`
    /// is `String?`, so its decode throws. With a flattened fallback this request would have been
    /// scoped to `(solana, bad-checksum address)` — a chain and an address `chain.inScope` and
    /// `address.format` never looked at, because once `watchlist` is present they read only it.
    @Test
    func aBlobTheChecksAcceptButWatchTargetRejectsNeverFallsBackToTheFlattenedPair() {
        let request = OperatorRequest(parameters: [
            "watchlist": #"[{"chain":"ethereum","address":"\#(vitalik)","label":5}]"#,
            "chain": "solana",
            "address": "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96044"
        ])
        #expect(request.watchlist.isEmpty)
        #expect(request.watchlist.map(\.chain) != ["solana"])
    }

    /// Replaces a test of `OperatorRequest.isEmpty`, which is gone.
    ///
    /// That test's assertions were right and its stated reason was not: its doc comment said the
    /// distinction was load-bearing because "`RuntimeHost.runOperator` substitutes the catalog's
    /// seed parameters when `isEmpty` is true" — a mechanism this branch deliberately deleted along
    /// with `OperatorSpec.defaultParameters`. So the suite was telling a future reader that a
    /// removed branch depended on a predicate nothing called.
    ///
    /// `toParameters()` is the real encoder of scope, so that is what gets pinned. It also closes
    /// the inconsistency the old predicate carried: `isEmpty` tested `query?.isEmpty` *untrimmed*
    /// while this trims, and its fixtures only ever used `""`, never `"   "`.
    @Test("toParameters encodes scope, trims blank values, and keeps attribution separate")
    func toParametersEncodesScopeAndTrimsBlanks() {
        #expect(OperatorRequest().toParameters().isEmpty)
        #expect(OperatorRequest(query: "   ").toParameters().isEmpty)
        #expect(OperatorRequest(identityID: "  ").toParameters().isEmpty)

        // `playbookID` is attribution for the run, not scope — but it must still be carried, which
        // is precisely what the deleted seed branch got wrong: a request holding only a playbook id
        // took the seed path and dropped it.
        #expect(OperatorRequest(playbookID: "research.brief").toParameters() == ["playbookID": "research.brief"])

        #expect(OperatorRequest(query: "  gas  ").toParameters()["query"] == "gas")

        let scoped = OperatorRequest(watchlist: [WatchTarget(chain: "base", address: vitalik)])
        let parameters = scoped.toParameters()
        #expect(parameters["chain"] == "base")
        #expect(parameters["address"] == vitalik)
        #expect(parameters["watchlist"] != nil)
    }

    /// The chain key is the governance stack's, not a lexical one — the two defects it closes are
    /// recorded on ``WatchTarget/chainKey(_:)``.
    @Test("watch targets key on a canonical chain, so aliases and stray whitespace are one target")
    func watchTargetIdentityIsCanonicalAcrossChainSpellings() {
        let canonical = WatchTarget(chain: "eth-mainnet", address: vitalik)

        // Aliases. Lexically seven different chains; one chain to `chain.inScope`, and now one here.
        for alias in ["ethereum", "eth", "mainnet", "1", "0x1", "eip155:1", "ETH-MAINNET"] {
            #expect(WatchTarget(chain: alias, address: vitalik).id == canonical.id, "\(alias)")
        }

        // Whitespace. This is the half that made one event satisfy two "distinct" targets, because
        // the id did not trim while the composer's matcher did.
        #expect(WatchTarget(chain: " ethereum ", address: vitalik).id == canonical.id)

        // A chain nothing resolves still compares consistently with itself, and does not collapse
        // into the same bucket as every other unresolvable chain.
        #expect(
            WatchTarget(chain: " NotAChain ", address: vitalik).id
                == WatchTarget(chain: "notachain", address: vitalik).id
        )
        #expect(
            WatchTarget(chain: "notachain", address: vitalik).id
                != WatchTarget(chain: "alsonotachain", address: vitalik).id
        )
    }
}

@Suite("Empty operator data source")
struct EmptyOperatorDataSourceTests {
    /// The unconfigured default returns nothing for any request. It exists so a runtime with no
    /// data source still composes a well-formed, visibly empty artifact rather than a fabricated
    /// one — the report says "no matching local activity", which is a true statement about what was
    /// read.
    @Test
    func returnsNoActivityForAnyRequest() async {
        let source = EmptyOperatorDataSource()
        let scoped = OperatorRequest(
            query: "anything",
            watchlist: [WatchTarget(chain: "ethereum", address: "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045")],
            identityID: "did:example:123"
        )
        #expect(await source.recentActivity(matching: scoped, limit: 50).isEmpty)
        #expect(await source.recentActivity(matching: OperatorRequest(), limit: 0).isEmpty)
    }
}

@Suite("Scope text sanitization")
struct ScopeTextSanitizationTests {
    /// Every scalar that can render as a line break, hide itself, or reorder the text around it has
    /// to be flattened — not just `\n`.
    ///
    /// The sanitizer's claim is that `CharacterSet.controlCharacters` (Unicode `Cc` *and* `Cf`) plus
    /// `.whitespacesAndNewlines` together cover the lot. That claim was made in a doc comment and
    /// never tested, and it is the whole basis for the composer's "caller prose stays prose"
    /// guarantee: U+2028 LINE SEPARATOR breaks a line without being a control character, U+202E
    /// RIGHT-TO-LEFT OVERRIDE reverses everything after it without being whitespace, and U+200B/
    /// U+FEFF are invisible. A scalar that survives here is a scalar a caller can put inside a
    /// heading this package signs its name to.
    @Test(arguments: [
        "\u{000B}", "\u{000C}", "\u{0085}",          // VT, FF, NEL
        "\u{2028}", "\u{2029}",                      // LINE / PARAGRAPH SEPARATOR
        "\u{00AD}", "\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}", // invisibles
        "\u{200E}", "\u{200F}",                      // LRM / RLM
        "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}", // embeddings / override
        "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}",             // isolates
        "\u{00A0}", "\u{1680}", "\u{202F}", "\u{3000}"              // exotic spaces
    ])
    func everyBreakingOrReorderingScalarIsFlattened(scalar: String) {
        let sanitized = WatchTarget.sanitizedProseText("left\(scalar)right")
        #expect(sanitized == "left right", "\(scalar.unicodeScalars.map { String($0.value, radix: 16) }) survived")
    }

    /// The scalars the set above misses: invisible, but neither control characters nor whitespace.
    ///
    /// The sibling test states the property as "renders as a break, hides itself, or reorders the
    /// text around it", and `Cc`/`Cf` + `.whitespacesAndNewlines` covers all of that except part of
    /// *hides itself*. The Hangul fillers are `Lo` — ordinary letters to every `CharacterSet` here —
    /// and they render as blank, which is what makes them the standard material for an invisible
    /// name.
    ///
    /// The surface is ``WatchTarget/displayName``, whose ladder is built on "a value that names
    /// nothing falls through to the next rung" — pinned for `""`, spaces and control characters by
    /// `aLabelThatNamesNothingFallsThroughToTheNextRung`, and not for these. A `label` of
    /// `"\u{3164}\u{3164}"` was a non-empty name that stopped the ladder, so the watch report's
    /// `## heading`, the artifact title and the `ToolCallArtifact.summary` that becomes the
    /// receipt's — for a high-risk `draftTransaction` packet — named no account at all, while the
    /// ENS and address rungs that would have named one were never reached.
    ///
    /// **The last three arguments are why this is a property and not a list.** Flattening the four
    /// Hangul fillers closed four spellings of the defect, not the defect: `U+2800` BRAILLE PATTERN
    /// BLANK is an ordinary `So` symbol that prints nothing, `U+034F` COMBINING GRAPHEME JOINER is
    /// a mark that renders nothing, and `U+180B` is one of the Mongolian free variation selectors —
    /// none of them whitespace, none of them control characters, none of them in the hand-written
    /// set, and every one of them a blank approval title. The rule is now Unicode's own
    /// `Default_Ignorable_Code_Point` property (which covers the fillers, the joiner, the Mongolian
    /// selectors and the tag characters) plus the braille blank, which the property does not claim.
    @Test(arguments: [
        "\u{115F}", "\u{1160}", "\u{3164}", "\u{FFA0}",
        "\u{2800}", "\u{034F}", "\u{180B}"
    ])
    func invisibleFillerScalarsAreFlattenedToo(scalar: String) {
        #expect(WatchTarget.sanitizedProseText("left\(scalar)right") == "left right")

        // A name made only of fillers names nothing, so the ladder keeps descending.
        let labelled = WatchTarget(chain: "ethereum", address: vitalik, ens: "treasury.eth", label: scalar + scalar)
        #expect(labelled.displayName == "treasury.eth")
        let unnamed = WatchTarget(chain: "ethereum", address: vitalik, ens: scalar, label: scalar)
        #expect(unnamed.displayName == "0xd8dA…6045")
    }

    /// …and the flattening stops there. Variation selectors are default-ignorable too, so a rule
    /// written as "remove every invisible scalar" would strip `U+FE0F` and break the emoji this
    /// package's own activity bullets render.
    @Test
    func emojiPresentationSelectorsSurviveFlattening() {
        #expect(WatchTarget.sanitizedProseText("⚠️ check this") == "⚠️ check this")
        #expect(WatchTarget.flattenedText("✅ done") == "✅ done")
        // The emoji this package's own bullets use, as scalars, so the carve-out is pinned on the
        // exact sequences `OperatorArtifactComposer.bullet` renders rather than on source literals.
        #expect(WatchTarget.flattenedText("\u{26A0}\u{FE0F}") == "\u{26A0}\u{FE0F}")
        // An ideographic variation sequence uses the supplementary selectors, which are carved out
        // for the same reason.
        #expect(WatchTarget.flattenedText("\u{845B}\u{E0100}") == "\u{845B}\u{E0100}")
    }

    /// A variation selector is not content: it changes how the character *before* it is presented,
    /// so one with nothing before it renders as nothing at all.
    ///
    /// The carve-out above is what keeps `⚠️` intact, and it was unconditional — so the exemption
    /// written for "do not break the composer's own emoji" also exempted a `label`, a `query`, or a
    /// remote provider's whole response body made only of selectors. That is the same blank-name /
    /// blank-body defect the filler scalars were added to close, arriving through the escape hatch
    /// cut for the fix: a high-risk `draftTransaction` packet whose title names no account, and an
    /// artifact body that renders empty while `ArtifactProvenance.inference` credits a model with
    /// writing it.
    @Test(arguments: ["\u{FE0F}", "\u{FE0E}", "\u{FE0F}\u{FE0F}\u{FE0E}", "\u{E0100}"])
    func aVariationSelectorWithNothingToModifyIsNotContent(scalar: String) {
        #expect(WatchTarget.flattenedText(scalar).isEmpty)
        // Including when what precedes it is only whitespace, which modifies nothing either.
        #expect(WatchTarget.sanitizedProseText(" \(scalar) ") == nil)
        #expect(WatchTarget.sanitizedProseText("left\(scalar)right") == "left\(scalar)right")

        let unnamed = WatchTarget(chain: "ethereum", address: vitalik, ens: scalar, label: scalar)
        #expect(unnamed.displayName == "0xd8dA…6045")
    }

    /// Truncation at the bound counts `Character`s, so it cannot split a grapheme cluster into
    /// something that renders differently from either half — and it cannot re-open a block, because
    /// it only ever removes trailing characters from a string whose first character has already
    /// been escaped.
    @Test
    func truncationCutsWholeGraphemesAndCannotReopenABlock() {
        // A combining-mark cluster, repeated past the 200-character bound.
        //
        // Deliberately *not* a ZWJ emoji sequence, and an earlier version of this comment claimed
        // one. U+200D is `Default_Ignorable_Code_Point`, so `flattenedText` replaces it with a space
        // — `"👩\u{200D}🚀"` flattens to `"👩 🚀"` — which is the intended behaviour and is pinned
        // separately by `everyBreakingOrReorderingScalarIsFlattened`. A ZWJ sequence therefore
        // *cannot* satisfy the assertion below, and a reader trusting the old comment would have
        // concluded that ZWJ clusters survive truncation and that the variation-selector carve-out
        // in `isVariationSelector` should be widened to include U+200D — which would reopen the
        // invisible-label and invisible-provider-body hole `rendersAsNothingAlone` exists to close.
        let cluster = "e\u{0301}"
        let long = String(repeating: cluster, count: 400)
        let sanitized = WatchTarget.sanitizedProseText(long)
        #expect(sanitized?.count == 200)
        // Every retained character is the whole cluster, never a bare combining mark.
        #expect(sanitized?.dropLast().allSatisfy { $0 == "é" } == true)
        #expect(sanitized?.last == "…")

        // Escaping survives truncation: the leading marker is escaped on the already-bounded text.
        let forged = "#" + String(repeating: "a", count: 400)
        let line = WatchTarget.lineSafeProseText(forged)
        #expect(line?.hasPrefix("\\#") == true)
        #expect(line?.hasSuffix("…") == true)
    }
}
