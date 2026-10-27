import AuralisCrypto
import Foundation
import AuralisRuntime

// There is deliberately no `ScopeText` helper here. It was a second, unreferenced copy of the
// sanitizer below — same flatten-and-bound body at a different ceiling (64 rather than
// ``WatchTarget/maximumProseLength``) — and nothing in the repo ever called it, so its bound was
// never the one any value actually got. It is deleted rather than wired up or left in place,
// because what it carried was worse than duplication: its documentation stated the rule
// "``singleLine(_:)`` guarantees the value cannot *contain* a line break; the composer is
// responsible for never placing it at the *start* of one … the composer prefixes it", and the
// composer did not. `composeResearch` and `composePreparedAction` both rendered caller prose at
// column 0, which is exactly how a one-line `"## Target"` forged a heading above the deterministic
// block naming the account — the defect ``WatchTarget/lineSafeProseText(_:)`` exists to close.
//
// So this was a dead helper asserting, at the single site this package has taken repeat defects on,
// the belief that produced them. The next person extending the composer would have read it as the
// contract. Same reasoning as the deleted `OperatorRequest.isEmpty` below: an unread declaration
// with contested semantics is how that bug happened; it is deleted rather than corrected. The
// accurate statement of all of this lives on the sanitizers that are actually called.

/// A single account/contract an operator is asked to watch or scope to. (P1-702)
public struct WatchTarget: Identifiable, Equatable, Sendable, Codable {
    public let chain: String
    public let address: String
    public let ens: String?
    public let label: String?

    public var id: String { "\(WatchTarget.chainKey(chain)):\(WatchTarget.addressKey(address))" }

    /// Address identity for keying and comparison, canonicalized to the one spelling the governed
    /// surfaces require.
    ///
    /// The other half of `chainKey`, and it was missing. The chain half trims and canonicalizes
    /// while this one only lowercased, so the identical asymmetry `chainKey` was introduced to fix
    /// survived on the address: `"0xabc…"` and `"0xabc… "` produced two distinct `id`s, so one
    /// account rendered under two headings and the padded one matched nothing — `matches` compared
    /// with `caseInsensitiveCompare`, which compares lengths. `AddressFormatCheck` does not catch
    /// it either, because `AuralisEthereumAddress` trims before validating, so both spellings pass.
    ///
    /// The `0x` prefix is normalized for the same reason, one level up: `AddressFormatCheck`
    /// accepts a bare 40-hex string and treats it as the same address as its prefixed form, while a
    /// lexical key treats them as two. That mismatch split one account's events across two targets
    /// *and* could put an unprefixed value into `preparedActionAddress`, which
    /// `ToolSchemaField.Kind.address` rejects — after the artifact has already been persisted.
    /// Keying on the prefixed form keeps this agreeing with the check that admits the value.
    ///
    /// Lexical rather than via `AuralisEthereumAddress` because this package deliberately depends
    /// only on `AuralisRuntime` and `AuralisReceipts`, and the normalization that matters here — trim,
    /// fold case, one prefix spelling — needs no address validation to perform. Anything that is
    /// not a 40-hex body is left alone rather than collapsed, so an unrecognized value still
    /// compares consistently with itself.
    public static func addressKey(_ address: String) -> String {
        normalizedAddress(address).lowercased()
    }

    /// Whether `character` is an *ASCII* hexadecimal digit.
    ///
    /// `Character.isHexDigit` is not ASCII-restricted: it is true for the fullwidth digit forms
    /// (`０`–`９`, U+FF10…) and other Unicode digit variants. ``ToolSchemaField/Kind/address`` and
    /// `AuralisEthereumAddress` both refuse those deliberately — AuralisRuntime records the defect
    /// where a 40-character address made entirely of fullwidth digits cleared a plain
    /// `allSatisfy(\.isHexDigit)` and reached `draftTransaction`.
    ///
    /// This function is the reason ``normalizedAddress(_:)`` can make the promise in its own
    /// documentation. With the permissive test, a 40-character non-ASCII body satisfied the
    /// `body.count == 40` branch and got a `0x` prefix *prepended* — manufacturing an
    /// address-shaped value out of input that is not an address, which the output schema then
    /// rejects after the artifact has already been persisted. Admitting only the characters the
    /// validating layers admit keeps this normalizer from inventing a shape they will refuse.
    private static func isASCIIHexDigit(_ character: Character) -> Bool {
        character.isASCII && character.isHexDigit
    }

    /// The address in the one spelling the governed surfaces accept, **with its case preserved**.
    ///
    /// Distinct from ``addressKey(_:)`` on purpose. Keying folds case, because `0xABC…` and
    /// `0xabc…` are one account and must be one target. A value that will be *shown to a human* or
    /// validated as an `.address` output field must not be folded: the mixed case in a
    /// checksummed address **is** the EIP-55 integrity check, and lowercasing it throws away the
    /// protection against a mistyped or substituted address on the approval surface — the exact
    /// surface `preparedActionAddress` feeds.
    ///
    /// So this trims and supplies the `0x` prefix (`ToolSchemaField.Kind.address` requires it,
    /// while `AddressFormatCheck` accepts a bare 40-hex body, and that disagreement would otherwise
    /// fail output validation *after* the artifact had been persisted) and changes nothing else.
    ///
    /// The *refusal* branch is flattened, which is the last raw interpolation in this feature. A
    /// recognized address cannot contain a break, so the returned `"0x" + body` is unchanged
    /// character for character; a value this normalizer declines to coerce used to come back as the
    /// caller's string with only its ends trimmed, and that string is interpolated into lines
    /// ``OperatorArtifactComposer`` owns — `` `<address>` ``, `- Address: `<address>``, and the
    /// restored `` - `<address>` on <chain> ``. An interior break there ends the composer's line and
    /// writes an unowned one into a durable, receipted artifact, which is precisely the defect
    /// ``flattenedChain(_:)`` was added for on the value sitting beside this one.
    ///
    /// Today the governed path refuses such a value upstream — `AddressFormatCheck` now rides on
    /// every operator and `AuralisEthereumAddress` calls it malformed — so this is defence in depth
    /// rather than a live hole. It is worth having because the composer is `public` and cannot
    /// require that check to have run, and because "every untrusted value this file renders is
    /// flattened" is a property that should hold by construction instead of by a neighbour's
    /// invariant. Keying stays consistent: ``addressKey(_:)`` folds whatever this returns.
    public static func normalizedAddress(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X")
            ? String(trimmed.dropFirst(2))
            : trimmed
        guard body.count == 40, body.allSatisfy(isASCIIHexDigit) else { return flattenedText(trimmed) }
        return "0x" + body
    }

    /// The chain in the spelling that is *rendered* and carried across the `ToolCallArtifact`
    /// boundary — the caller's own, flattened to one line.
    ///
    /// The address half of a target goes through ``normalizedAddress(_:)`` at every site that shows
    /// it to a human or hands it to the output schema; the chain half went through nothing, and it
    /// is the one untrusted value ``OperatorArtifactComposer`` still interpolated raw — at the end
    /// of `## <name> — <chain>`, of `- Chain: <chain>`, and of the restored
    /// `` - `<address>` on <chain> `` line, as well as into `preparedActionChain`.
    ///
    /// That is reachable *through* `chain.inScope`, not around it: `ChainScopeReference.resolve`
    /// trims `.whitespacesAndNewlines` before matching, so `"ethereum\n"` and `"\u{2028}ethereum"`
    /// resolve to Ethereum mainnet and pass the check — and then end the composer's line early,
    /// splitting a heading the composer owns and writing a stray line it never composed into a
    /// durable, receipted artifact. The same string reaches a receipt field verbatim.
    ///
    /// Flattening, never resolving. An unresolvable chain must still render as the thing the caller
    /// named, for the same reason ``chainKey(_:)`` keeps unknown chains distinct from one another
    /// rather than collapsing them into one bucket — and because resolving here would make the
    /// artifact name a chain the caller did not type.
    public static func flattenedChain(_ chain: String) -> String {
        flattenedText(chain)
    }

    /// Chain identity for keying and comparison, resolved the way the governance stack resolves it.
    ///
    /// Two separate defects came from this not existing. The first was *narrower* than `inScope`:
    /// this key used a bare `lowercased()` while the composer's matcher trimmed as well, so
    /// `"ethereum"` and `" ethereum"` were two distinct targets that one event satisfied twice —
    /// rendering the account under two spellings, double-counting its alerts, and queueing two
    /// identical prepared actions, which is exactly what the composer's own comment declared
    /// impossible.
    ///
    /// The second was *wider*, and worse. `chain.inScope` canonicalizes through
    /// ``ChainScopeReference/resolve(_:)``, which knows `ethereum`, `eth`, `mainnet`, `eth-mainnet`,
    /// `1`, `0x1` and `eip155:1` are one chain — while lexical comparison treats them as seven. A
    /// watch scoped as `"ethereum"` passed the check and then matched nothing in a ledger that
    /// records `"eth-mainnet"`, so a monitoring operator wrote a durable artifact and a receipt
    /// saying "_No recent observed activity._" against a ledger full of matching events. Silently
    /// reporting clean is the worst failure mode a watch has.
    ///
    /// Falls back to the trimmed, lowercased original so an unresolvable chain is still compared
    /// consistently with itself rather than collapsing every unknown chain into one bucket.
    /// `public` because the *narrowing* happens in `AuralisAppShell.ReceiptBackedOperatorDataSource`,
    /// which runs before the composer and must use the same key. Fixing only the composer left the
    /// data source as the narrow half: it dropped the records on an exact-lowercase mismatch, so the
    /// composer's canonical matcher never saw them and the watch still reported clean.
    public static func chainKey(_ chain: String) -> String {
        ChainScopeReference.resolve(chain)?.rawValue
            ?? chain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public init(chain: String, address: String, ens: String? = nil, label: String? = nil) {
        self.chain = chain
        self.address = address
        self.ens = ens
        self.label = label
    }

    /// The longest a rendered ``displayName`` may be.
    ///
    /// `label` is unbounded on the way in — it is decoded out of the untrusted `watchlist` JSON —
    /// and on the way out it lands in `Artifact.title` and in the `ToolCallArtifact.summary` that
    /// becomes the receipt's. `ArtifactSchema.problems(title:content:)` bounds *content* and only
    /// requires the title to be non-blank, so nothing downstream caps either one. The ceiling is
    /// well under `ens.format`'s 255 because this is documented as a *short* name and is composed
    /// into headings, not a field of its own.
    static let maximumDisplayNameLength = 64

    /// `value` reduced to a single bounded line of printable text, or `nil` when nothing printable
    /// is left — in which case ``displayName`` keeps descending its ladder.
    ///
    /// `label` is the one scope field no deterministic check validates, and it outranks the one that
    /// is validated. `chain` goes through `chain.inScope`, `address` through `address.format`, and
    /// `ens` through `ens.format` — which, as ``OperatorCatalog`` records, was put on every operator
    /// precisely because ``displayName`` prefers the ENS name and an unchallenged homoglyph "became
    /// the title of an approval". `label` sits above `ens` on that ladder and nothing looks at it.
    ///
    /// What it could do with that is structural rather than cosmetic. `displayName` is interpolated
    /// into Markdown headings this package composes and signs its name to — `## \(displayName) —
    /// \(chain)` in the watch, `# Prepared Action Packet: \(displayName)` in the packet — and a
    /// heading only begins at the start of a line. A label carrying a newline therefore wrote its
    /// own `## Target` block into the deterministic body, ahead of the composer's and naming an
    /// address the run never prepared, in the one artifact a human reads before approving a
    /// high-risk `draftTransaction`. That is the same "approval surface disagreeing with the record
    /// behind it" `OperatorArtifactComposer.enforcingPreparedTarget` exists to prevent, reaching the
    /// path it does not cover: those restorations run only on the remote route, and this needs no
    /// provider at all.
    ///
    /// Line breaks are collapsed rather than deleted so two words do not fuse into one, and
    /// `.newlines` is applied on top of `.controlCharacters` because U+2028/U+2029 break a line
    /// without being control characters.
    ///
    /// Deliberately *not* a character allowlist. A label is a user's nickname for an account, so
    /// refusing non-ASCII would reject legitimate names; the ENS rung can be that strict because an
    /// ENS name is a protocol identifier with a defined alphabet. Flattening and bounding are the
    /// properties that hold for any label, and they are the ones that carry governance weight.
    static func sanitizedDisplayText(_ value: String?) -> String? {
        sanitizedText(value, limit: maximumDisplayNameLength)
    }

    /// The bound for free prose the caller supplies — `query` and `identityID`.
    ///
    /// Larger than ``maximumDisplayNameLength`` because these are sentences rather than names, and
    /// still a bound because both are composed into the artifact *title* and the
    /// `ToolCallArtifact.summary` that becomes the receipt's, neither of which anything downstream
    /// caps.
    static let maximumProseLength = 200

    /// ``sanitizedDisplayText`` for caller-supplied prose.
    ///
    /// `label` was found first, but it is not the only field on this path: `query` reached the
    /// research brief's title, its `## Query` section and its summary with **no** sanitization at
    /// all, and `identityID` reached the identity review's title and scope lines through a
    /// `trimmingCharacters(in: .whitespacesAndNewlines)` that strips the *ends* of a string and
    /// leaves its interior untouched. Neither has a deterministic check behind it — there is no
    /// `query.format` — so both carried a newline straight into prose this package composes and
    /// signs its name to, and could open a `## Target` block of their own ahead of the composer's.
    /// `RuntimeHost.runResearchBrief(query:watchlist:)` is public, so the value is whatever the
    /// caller passed.
    static func sanitizedProseText(_ value: String?) -> String? {
        sanitizedText(value, limit: maximumProseLength)
    }

    /// ``sanitizedProseText(_:)`` additionally made safe to place at the **start of a line**.
    ///
    /// Flattening and being non-structural are two different properties, and the sanitizers above
    /// supply only the first. A Markdown block — ATX heading, list item, blockquote, fence, table
    /// row, HTML block, link reference definition — begins at the start of a line, and *one line is
    /// all it needs*: `"## Target"` carries no line break for the flattener to collapse, so it
    /// reached `composePreparedAction`'s `## Intended action` section verbatim and rendered a second
    /// `## Target` heading **above** the composer's own, naming an address the run never prepared,
    /// in the artifact a human reads before approving a high-risk `draftTransaction`. That is the
    /// round-5 `label` defect reaching the same surface through a one-line value, and the only
    /// reason flattening looked sufficient is that the test that pinned it used a multi-line input
    /// whose *first* word was ordinary prose.
    ///
    /// So the two sites that render caller prose as a line of its own go through this instead. The
    /// treatment is a backslash escape of the leading token rather than a quote or a code span:
    /// CommonMark resolves `\#` to a literal `#`, so the caller's sentence still renders verbatim
    /// and in full — which a code span would mangle (a backtick in the prose closes it early) and a
    /// blockquote would not even fix, because a blockquote's content is parsed as Markdown too and
    /// `> ## Target` is still a heading.
    ///
    /// Escaping happens *after* truncation, deliberately: adding the backslash first and cutting
    /// later could strand it, and cutting first cannot re-open a block because truncation only
    /// removes trailing characters from a string whose first character has already been judged.
    static func lineSafeProseText(_ value: String?) -> String? {
        guard let text = sanitizedProseText(value) else { return nil }
        return escapingLeadingBlockMarker(text)
    }

    /// The characters a Markdown block can open with. Deliberately wider than the strict CommonMark
    /// rule (`#foo` is not a heading, only `# foo` is): over-escaping costs a backslash that renders
    /// as nothing, and under-escaping costs a forged heading on an approval surface.
    ///
    /// `|` is here for GFM tables, `<` for HTML blocks, `[` for link reference definitions, `=` and
    /// `-` for setext underlines, `` ` `` and `~` for fences, `*`/`_`/`-` for thematic breaks and
    /// list items, `>` for blockquotes.
    private static let blockOpeningCharacters: Set<Character> = [
        "#", ">", "-", "+", "*", "_", "=", "~", "`", "<", "[", "|"
    ]

    private static func escapingLeadingBlockMarker(_ text: String) -> String {
        guard let first = text.first else { return text }
        if blockOpeningCharacters.contains(first) { return "\\" + text }
        // An ordered list opens with digits and a `.` or `)`, so the escape goes on the delimiter
        // rather than the first character.
        let digits = text.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty else { return text }
        let remainder = text.dropFirst(digits.count)
        guard let delimiter = remainder.first, delimiter == "." || delimiter == ")" else { return text }
        return String(digits) + "\\" + String(remainder)
    }

    /// `value` reduced to a single line of printable text with runs of whitespace collapsed.
    /// **Unbounded** — the structural half of the treatment, without the length half.
    ///
    /// Split out of ``sanitizedText(_:limit:)`` for the one caller that needs flattening but must
    /// not shorten what it renders: ``OperatorArtifactComposer``'s activity bullets. Those carry
    /// `ObservedActivity.title`/`detail`, which are *not* scope strings and not the caller's to
    /// bound — they are whatever the `OperatorDataSource` observed — but they are interpolated into
    /// a `- ` list line in a body this package composes, and a line break in one of them ends the
    /// bullet and starts a structural line the composer never wrote.
    ///
    /// That is reachable, not theoretical: `ReceiptBackedOperatorDataSource` maps `record.summary`
    /// straight onto `title`, and `RuntimeHost` writes receipt summaries built from free text
    /// (`"Autopilot planned “\(goal.text)” with model routing"`). So a goal carrying a newline put
    /// a forged `##` section and a forged `- Address:` line inside a research brief, a watch report
    /// and an identity review — the same defect found on `label` and `query`, arriving through the
    /// feed rather than through the request.
    ///
    /// No escaping here, unlike ``lineSafeProseText(_:)``: the composer owns the `- ` marker at the
    /// start of these lines, so once the value cannot contain a break it cannot open a block.
    ///
    /// Line breaks collapse to a space rather than being deleted so two words do not fuse into one.
    /// `.whitespacesAndNewlines` is applied on top of `.controlCharacters` because U+2028/U+2029
    /// break a line without being control characters; between them the two sets cover every scalar
    /// that renders as a break or reorders the text around it (`.controlCharacters` is Unicode `Cc`
    /// *and* `Cf`, so the bidi overrides, the zero-width family and U+FEFF are already in it).
    /// Pinned by `everyBreakingOrReorderingScalarIsFlattened`.
    ///
    /// ``rendersAsNothingAlone(_:)`` closes the gap in that claim — see there.
    static func flattenedText(_ value: String) -> String {
        var scalars = String.UnicodeScalarView()
        // Whether the scalar just retained is something a variation selector could be modifying.
        // A selector is not content; it changes how the character *before* it is presented, so one
        // with nothing before it renders as nothing at all. See ``isVariationSelector(_:)``.
        var previousIsModifiable = false
        for scalar in value.unicodeScalars {
            if rendersAsNothingAlone(scalar) || (isVariationSelector(scalar) && !previousIsModifiable) {
                scalars.append(" ")
                previousIsModifiable = false
            } else {
                scalars.append(scalar)
                previousIsModifiable = !CharacterSet.whitespacesAndNewlines.contains(scalar)
            }
        }
        return String(scalars)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Whether `scalar` renders as nothing when it stands on its own — the half of
    /// ``flattenedText(_:)``'s promise that neither `CharacterSet.controlCharacters` nor
    /// `.whitespacesAndNewlines` can express.
    ///
    /// The sanitizer's stated property — and the one its test suite names — is that a scalar which
    /// "renders as a break, hides itself, or reorders the text around it" cannot survive into prose
    /// this package signs its name to. `Cc`/`Cf` plus `.whitespacesAndNewlines` covers the breaking
    /// and reordering halves completely, and only *part* of the hiding half.
    ///
    /// The surface that matters is ``displayName``, whose whole ladder is built on "a value that
    /// names nothing falls through to the next rung" — the property
    /// `aLabelThatNamesNothingFallsThroughToTheNextRung` pins for `""`, spaces and control
    /// characters. A `label` made only of invisible scalars is none of those, so it survived as a
    /// non-nil, non-empty name, stopped the ladder, and became a blank `## heading` in a watch
    /// report and a blank `# Prepared Action Packet:` title — the artifact title and the receipt
    /// summary for a high-risk `draftTransaction` naming no account at all, with the ENS name and
    /// address rungs that *would* have named one never consulted. Interior use is the milder half
    /// of the same thing: `"Treas\u{3164}ury"` reads as `Treasury` and compares equal to nothing.
    /// The same question decides whether a remote provider's response body is content at all —
    /// see `OperatorExecutor`'s `bodyIsModelAuthored`.
    ///
    /// This was a hand-written set of four Hangul fillers, and a hand-written set is the wrong
    /// shape for this question: `"\u{2800}"` (BRAILLE PATTERN BLANK) and `"\u{034F}"` (COMBINING
    /// GRAPHEME JOINER) are just as blank, just as easy to type, and were not in it — so the same
    /// blank-approval-title and blank-provider-body defects the fillers were added to close were
    /// still reachable under a different spelling. Unicode already maintains the list, as
    /// `Default_Ignorable_Code_Point`, which covers all four fillers plus the joiners, the
    /// Mongolian free variation selectors, the unassigned-but-ignorable blocks and the tag
    /// characters. Asking the property is the rule; the explicit set below is only for scalars the
    /// property does *not* claim.
    ///
    /// Variation selectors are the one carve-out, because flattening those would break the emoji
    /// this package's own bullets render (`⚠️` is U+26A0 U+FE0F) — see ``isVariationSelector(_:)``.
    private static func rendersAsNothingAlone(_ scalar: Unicode.Scalar) -> Bool {
        if isVariationSelector(scalar) { return false }
        if CharacterSet.controlCharacters.contains(scalar) { return true }
        if scalar.properties.isDefaultIgnorableCodePoint { return true }
        return additionalBlankScalars.contains(scalar)
    }

    /// Scalars that render blank without being default-ignorable, so the property above misses them.
    ///
    /// U+2800 is a braille cell with every dot unset: Unicode gives it `So`, no `White_Space`, and
    /// no `Default_Ignorable` — an ordinary printing symbol that prints nothing. It is the standard
    /// material for an invisible name precisely because it survives every "is this whitespace or a
    /// control character" test ever written.
    private static let additionalBlankScalars: Set<Unicode.Scalar> = [
        "\u{2800}" // BRAILLE PATTERN BLANK
    ]

    /// Whether `scalar` is a variation selector — the scalars ``rendersAsNothingAlone(_:)``
    /// deliberately refuses to call blank.
    ///
    /// They are `Default_Ignorable` like the fillers, and a rule written as "remove every invisible
    /// scalar" would strip `U+FE0F` and break the emoji this package's own activity bullets render.
    /// What makes them different is that they are never *standalone* text: a selector modifies the
    /// presentation of the character preceding it. ``flattenedText(_:)`` therefore keeps one that
    /// has a character to modify and flattens one that does not, so `"⚠️"` survives intact while a
    /// response or a label made only of selectors — which renders as nothing — does not pass for
    /// content.
    private static func isVariationSelector(_ scalar: Unicode.Scalar) -> Bool {
        (0xFE00...0xFE0F).contains(scalar.value) || (0xE0100...0xE01EF).contains(scalar.value)
    }

    private static func sanitizedText(_ value: String?, limit: Int) -> String? {
        guard let value else { return nil }
        let flattened = flattenedText(value)
        guard !flattened.isEmpty else { return nil }
        guard flattened.count > limit else { return flattened }
        return String(flattened.prefix(limit - 1)) + "…"
    }

    /// Short, human-facing name: explicit label, else ENS, else a truncated address.
    ///
    /// The address rung truncates the ``normalizedAddress(_:)`` spelling, not the raw one. This is
    /// the last site that rendered the caller's spelling after the body and the prepared packet were
    /// moved onto one: an unlabelled target becomes the `## heading` of its watch section, the
    /// `PreparedAction.title`, the artifact *title* of a prepared packet, and the watchlist row in
    /// Mission Control — all of which sit next to a `preparedActionAddress` that is normalized. A
    /// bare 40-hex entry, which `AddressFormatCheck` admits, therefore read `d8dA6B…6045` in the
    /// title above a packet for `0xd8dA6BF…6045`, and a padded one spent its whole elision budget on
    /// whitespace (`  0xd8…45  `), showing a human two fewer identifying characters than the short
    /// form is supposed to carry. Truncating the normalized spelling is case-preserving, so the
    /// EIP-55 signal in the retained characters survives.
    ///
    /// Every rung goes through ``sanitizedDisplayText(_:)``, so the value is flattened and bounded
    /// whichever one answers — which is what lets the composer interpolate it into a heading. It is
    /// *not* line-safe (see ``lineSafeProseText(_:)``) and does not need to be: every site that
    /// renders it prefixes it with composer-owned text.
    public var displayName: String {
        if let label = WatchTarget.sanitizedDisplayText(label) { return label }
        if let ens = WatchTarget.sanitizedDisplayText(ens) { return ens }
        // Already bounded (``shortAddress``) and already the spelling the packet carries, but run
        // through the same flattening so every rung of this ladder makes the same promise.
        let short = WatchTarget.shortAddress(WatchTarget.normalizedAddress(address))
        return WatchTarget.sanitizedDisplayText(short) ?? short
    }

    public static func shortAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))…\(address.suffix(4))"
    }
}

/// The caller-supplied inputs that make an operator run do *real* work rather than emit a canned body:
/// a research query, a watchlist of accounts/contracts, and/or the active identity to scope to.
/// (P1-701..703)
public struct OperatorRequest: Equatable, Sendable {
    public var query: String?
    public var watchlist: [WatchTarget]
    public var identityID: String?
    /// The playbook that initiated this run, when the operator is being used as a playbook step.
    public var playbookID: String?

    public init(
        query: String? = nil,
        watchlist: [WatchTarget] = [],
        identityID: String? = nil,
        playbookID: String? = nil
    ) {
        self.query = query
        self.watchlist = watchlist
        self.identityID = identityID
        self.playbookID = playbookID
    }

    // There is deliberately no `isEmpty` here. It was the reader for `runOperator`'s catalog-seed
    // branch, and that branch went away with `OperatorSpec.defaultParameters` — no production code
    // has called it since (`RuntimeHost.swift:1076` records the removal). Keeping it meant keeping
    // an unread predicate whose semantics had already drifted: it tested `query?.isEmpty`
    // *untrimmed* while `toParameters()` trims, so `OperatorRequest(query: "   ")` reported itself
    // non-empty while encoding to nothing, and it never considered `playbookID` at all — the exact
    // omission that made a playbook-only request take the seed branch and get silently dropped.
    // An unread predicate with contested semantics is how that bug happened; it is deleted rather
    // than corrected.

    /// Encodes the request into `ActionProposal.parameters`, keeping `address`/`chain`/`ens` on the
    /// primary target so the deterministic address/chain/ENS checks stay reproducible from the receipt.
    public func toParameters() -> [String: String] {
        var parameters: [String: String] = [:]
        if let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            parameters["query"] = query
        }
        if let identityID = identityID?.trimmingCharacters(in: .whitespacesAndNewlines), !identityID.isEmpty {
            parameters["identityID"] = identityID
        }
        if let playbookID = playbookID?.trimmingCharacters(in: .whitespacesAndNewlines), !playbookID.isEmpty {
            parameters["playbookID"] = playbookID
        }
        if let primary = watchlist.first {
            parameters["chain"] = primary.chain
            parameters["address"] = primary.address
            if let ens = primary.ens, !ens.isEmpty { parameters["ens"] = ens }
        }
        if !watchlist.isEmpty,
           let data = try? JSONEncoder().encode(watchlist),
           let json = String(data: data, encoding: .utf8) {
            parameters["watchlist"] = json
        }
        return parameters
    }

    /// Rebuilds the request from proposal parameters (the inverse of ``toParameters()``).
    ///
    /// The `watchlist` key being *present* decides the scope on its own, exactly as it does in
    /// AuralisRuntime's `CheckTargets.decode`: if it is there but unusable, the result is an empty
    /// watchlist, never the flattened `chain`/`address`/`ens` pair.
    ///
    /// The hazard this guards against is not a bad decode — it is two decoders disagreeing about
    /// which inputs win. The checks decode this same string as their own stricter entry shape and,
    /// once the key is present, ignore the flattened parameters entirely. So any disagreement about
    /// whether this blob is readable used to hand the executor a target the checks never examined:
    /// a blob the checks parse but `WatchTarget` rejects (say an entry whose `label` is a number)
    /// passed `address.format`/`chain.inScope`/`ens.format` against the *watchlist's* targets while
    /// the run composed against the flattened pair — an unchecked address, and for a
    /// `.preparedAction` operator an unchecked address inside the packet a human then approves.
    /// The fix is therefore to make this decoder's "present but unusable" answer match the checks'
    /// rather than to make it more permissive: the checks already fail a proposal whose watchlist is
    /// present and malformed, so an empty scope here can never be a scope they did not see.
    ///
    /// The flattened fallback stays for the case where `watchlist` is *absent* — a hand-built
    /// proposal, or a receipt written before the field existed. That is the legitimate single-target
    /// shape, and it is the shape the checks fall back to as well.
    ///
    /// It requires **both** `chain` and `address`, and names no target when either is missing.
    ///
    /// This used to default a missing chain to `"ethereum"`, justified as safe because
    /// "`chain.inScope` still gets to judge the result". It does not. `ChainScopeCheck` reads
    /// `proposal.parameters["chain"]`, and on a proposal that carries none `CheckTargets.decode`
    /// produces a target whose `chain` is `nil`, so the check returns `passed: true` with "no chain
    /// to check" — it never sees the invented value, because the invention happens here, after the
    /// check has run. The second half of the justification ("a watch cannot reach here without a
    /// chain, its input schema requires one") held only for the two operators that *declare* a
    /// `chain` field. Research Brief and Identity Review declare neither and their input schemas are
    /// `allowsAdditionalFields: true`, so a proposal carrying `address` with no `chain` passes
    /// schema validation, passes `chain.inScope` vacuously, and then ran against a chain nobody
    /// named: `LiveOnChainOperatorDataSource` resolves it and issues a live JSON-RPC read, and the
    /// chain is written into a durable, receipted artifact as the scope of the run. A policy whose
    /// `allowedChains` excluded Ethereum mainnet would have been bypassed by omission.
    ///
    /// This is the same rule ``OperatorCatalog`` states for `defaultParameters` and `RuntimeHost`
    /// states for a seedless `runOperator`: a catalog or decoder constant supplying scope is
    /// *fabricated* scope inside a governed run, and a refusal naming the missing input is the
    /// right answer. `WatchlistEntry` — the checks' own decoder for the JSON path — takes the same
    /// line, requiring `chain` and `address` rather than decoding either into `nil`.
    public init(parameters: [String: String]) {
        let query = parameters["query"]
        let identityID = parameters["identityID"]
        let playbookID = parameters["playbookID"]
        var watchlist: [WatchTarget] = []
        if let json = parameters["watchlist"] {
            if let data = json.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([WatchTarget].self, from: data) {
                watchlist = decoded
            }
        } else if let address = parameters["address"], !Self.isBlank(address),
                  let chain = parameters["chain"], !Self.isBlank(chain) {
            // *Blank* counts as absent, not merely empty. `ToolSchema.validationProblems` treats a
            // present-but-empty required field as missing, and `ToolSchemaField.Kind.chain` only
            // refuses `""` — so `"   "` clears both and then resolves to nothing, exactly the
            // "names a chain" / "names nothing" ambiguity the invented default exploited. The same
            // rule `toParameters()` applies to every other scope value it encodes.
            //
            // The values are carried through *untrimmed*: these are the strings the deterministic
            // checks were handed, and `WatchTarget` already trims at every point it keys or
            // validates. Trimming here would make the run's scope differ from the checked scope.
            watchlist = [WatchTarget(chain: chain, address: address, ens: parameters["ens"])]
        }
        self.init(query: query, watchlist: watchlist, identityID: identityID, playbookID: playbookID)
    }

    private static func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// What an observation actually says about the thing being watched.
///
/// Three states rather than a `Bool`, because "this on-chain action failed" and "we could not see
/// the chain" are different facts with different consequences and a boolean collapsed them. A watch
/// data source reports its *own* provider and network failures through this type, so an RPC timeout
/// was rendered into a durable, receipted artifact as `⚠️ 1 alert` on a watched account when nothing
/// had happened on chain at all — and the alert count went onto the receipt.
public enum ObservationOutcome: String, Sendable, Equatable, Codable {
    /// Observed, and the observed thing succeeded.
    case succeeded
    /// Observed, and the observed thing failed. This is the only outcome that is an *alert about the
    /// account*, and therefore the only one that can justify preparing an action.
    case failed
    /// Not observed. A monitoring gap — a statement about us, not about the account. Never counted
    /// as an alert and never a reason to prepare an action, because there is no finding behind it.
    case unobserved
}

/// A real, locally-observed event that an operator can reason over. Deliberately provider-neutral so
/// `AuralisOperators` needn't depend on `AuralisReceipts`; the runtime maps its receipt ledger onto this.
public struct ObservedActivity: Equatable, Sendable {
    /// Receipt that proves this observation, when it originated in the local receipt ledger.
    public let sourceReceiptID: UUID?
    public let title: String
    public let detail: String
    public let occurredAt: Date
    public let chain: String?
    public let address: String?
    public let identityID: String?
    public let outcome: ObservationOutcome

    /// Retained so existing ledger-backed producers and tests keep reading naturally. `.unobserved`
    /// is *not* a success, so this stays false for it — but callers deciding whether something is
    /// wrong with the watched account must ask `outcome == .failed`, not `!isSuccess`.
    public var isSuccess: Bool { outcome == .succeeded }

    public init(
        title: String,
        detail: String,
        occurredAt: Date,
        chain: String? = nil,
        address: String? = nil,
        identityID: String? = nil,
        sourceReceiptID: UUID? = nil,
        outcome: ObservationOutcome
    ) {
        self.title = title
        self.detail = detail
        self.occurredAt = occurredAt
        self.chain = chain
        self.address = address
        self.identityID = identityID
        self.sourceReceiptID = sourceReceiptID
        self.outcome = outcome
    }

    /// Source-compatible form for producers that only distinguish success from failure — the local
    /// receipt ledger, where every row *is* an observation and the question is only how it went.
    public init(
        title: String,
        detail: String,
        occurredAt: Date,
        chain: String? = nil,
        address: String? = nil,
        identityID: String? = nil,
        sourceReceiptID: UUID? = nil,
        isSuccess: Bool = true
    ) {
        self.init(
            title: title,
            detail: detail,
            occurredAt: occurredAt,
            chain: chain,
            address: address,
            identityID: identityID,
            sourceReceiptID: sourceReceiptID,
            outcome: isSuccess ? .succeeded : .failed
        )
    }
}

/// A confirm-first action an operator *prepared* but did not execute. Surfaced so it can be escalated
/// to the Approval Inbox for a human. (P1-702)
public struct PreparedAction: Equatable, Sendable {
    public let title: String
    public let chain: String
    public let address: String
    public let rationale: String

    public init(title: String, chain: String, address: String, rationale: String) {
        self.title = title
        self.chain = chain
        self.address = address
        self.rationale = rationale
    }
}

/// The read-only seam operators use to gather real inputs. Backed by the local receipt ledger in the
/// app; a no-op default keeps `AuralisOperators` self-contained and testable. (P1-701..703)
///
/// **Read-only, but not necessarily on-device.** This used to promise "never reaches outside the
/// device", and the app's own conforming type contradicted it: `LiveOnChainOperatorDataSource`
/// issues a bounded JSON-RPC balance read per watchlist entry. Read-only is the invariant that
/// actually holds — an implementation may not sign, submit, enumerate unrelated accounts, or widen
/// the caller's requested scope — and it is the one worth stating, because it is what keeps an
/// operator from needing unrestricted external authority. A conformer that does reach the network
/// owns the privacy claim about doing so; the composer deliberately makes none on its behalf.
public protocol OperatorDataSource: Sendable {
    /// Recent local activity relevant to the request (already filtered by query/watchlist/identity by
    /// the implementation), newest first, bounded by `limit`.
    func recentActivity(matching request: OperatorRequest, limit: Int) async -> [ObservedActivity]
}

/// A data source that returns nothing — the safe default so an unconfigured runtime still produces a
/// well-formed (if empty) artifact rather than a fake one.
public struct EmptyOperatorDataSource: OperatorDataSource {
    public init() { }

    public func recentActivity(matching request: OperatorRequest, limit: Int) async -> [ObservedActivity] {
        []
    }
}
