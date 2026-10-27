/// Whether inference happened on-device or off-device. Shared by ``ActorRef`` (attribution) and the
/// runtime's model-routing layer (telemetry), so provenance and routing speak the same vocabulary.
public enum InferenceLocality: String, Codable, CaseIterable, Sendable {
    case local
    case remote

    /// The trust-facing privacy impact implied purely by *where* inference ran (P1-AI-102). Derived
    /// from locality rather than stored separately, so it can never drift from the recorded fact:
    /// on-device work keeps inputs on the device; remote work sends them to a third-party provider.
    ///
    /// - Note: `AuralisReceipts` mirrors this mapping locally (it is a dependency-free leaf) — keep the
    ///   two in sync if the wording changes.
    public var privacyImpact: String {
        switch self {
        case .local:
            return "On-device — inputs stay on this device"
        case .remote:
            return "Sent to provider — inputs leave this device"
        }
    }

    /// A compact label for chips/badges where the full sentence doesn't fit.
    public var privacyImpactShort: String {
        switch self {
        case .local: return "On-device"
        case .remote: return "Off-device"
        }
    }
}

/// Where and how a model produced something, for trust/privacy attribution on receipts and worklogs.
public struct InferenceProvenance: Equatable, Hashable, Sendable, Codable {
    public let locality: InferenceLocality
    public let provider: String?
    public let modelClass: String?

    public init(locality: InferenceLocality, provider: String? = nil, modelClass: String? = nil) {
        self.locality = locality
        self.provider = provider
        self.modelClass = modelClass
    }

    /// Provenance for work performed on `route`, so attribution and model routing can't disagree
    /// about where inference ran.
    public init(route: ModelRoute) {
        self.init(locality: route.locality, provider: route.provider, modelClass: route.modelClass)
    }

    /// Convenience for on-device inference (Apple Foundation Models, local models).
    public static func local(modelClass: String? = nil) -> InferenceProvenance {
        InferenceProvenance(locality: .local, provider: nil, modelClass: modelClass)
    }

    /// The privacy impact implied by this provenance's locality (P1-AI-102).
    public var privacyImpact: String { locality.privacyImpact }

    private enum CodingKeys: String, CodingKey {
        case locality
        case provider
        case modelClass
    }

    /// Tolerant decoding for `locality`, for the same reason ``ActorRef/init(from:)`` tolerates an
    /// unknown `kind`: synthesized `Codable` throws on an unrecognized raw value, and that throw
    /// propagates out of the enclosing `ActorRef` decode into stores that read rows through
    /// `compactMap`/`try?` — so a third locality written by a newer build would delete the entire
    /// receipt, worklog entry, lease, session, or run rather than degrade one field.
    ///
    /// An unrecognized locality degrades to ``InferenceLocality/remote``, never `.local`. The value
    /// drives a user-facing privacy claim, and the only safe direction to be wrong in is the
    /// conservative one: asserting "inputs left this device" about work that stayed local is a
    /// harmless overstatement, while the reverse would be a false privacy guarantee.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawLocality = try container.decode(String.self, forKey: .locality)
        locality = InferenceLocality(rawValue: rawLocality) ?? .remote
        provider = try container.decodeIfPresent(String.self, forKey: .provider)
        modelClass = try container.decodeIfPresent(String.self, forKey: .modelClass)
    }
}

/// The kind of party responsible for an action, receipt, or worklog entry.
public enum ActorKind: String, Codable, CaseIterable, Sendable {
    case human
    /// An operator pack. Raw value stays `"operator"` for stable serialization; the case avoids the
    /// Swift keyword.
    case operatorAgent = "operator"
    case plugin
    case workflow
    case scheduledRoutine
    case model

    /// User-facing name for the kind. Lives here so trust surfaces never fall back to showing a raw
    /// serialization value like `"scheduledRoutine"`.
    public var displayTitle: String {
        switch self {
        case .human: return "Human"
        case .operatorAgent: return "Operator"
        case .plugin: return "Plugin"
        case .workflow: return "Workflow"
        case .scheduledRoutine: return "Scheduled routine"
        case .model: return "Model"
        }
    }
}

/// Structured attribution: who acted, under what identity, and — for model actors — with what
/// inference provenance. The typed successor to `ReceiptActor {user, system}`.
///
/// - Note: Identity attribution lives in AuralisRuntime so the kernel remains a light, independently
///   buildable leaf without pulling ENS/secp256k1 into its dependency graph.
public struct ActorRef: Equatable, Hashable, Sendable, Codable {
    public let kind: ActorKind
    /// Stable identifier for non-human actors (plugin id, workflow id, routine id, model id).
    public let identifier: String?
    public let displayName: String?
    /// Present when `kind == .model` (or a model-backed actor) to record local vs remote inference.
    public let inference: InferenceProvenance?

    public init(
        kind: ActorKind,
        identifier: String? = nil,
        displayName: String? = nil,
        inference: InferenceProvenance? = nil
    ) {
        let normalizedIdentifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind != .human {
            precondition(
                normalizedIdentifier?.isEmpty == false,
                "Non-human actors require a stable, non-empty identifier."
            )
        }
        if kind == .model {
            precondition(inference != nil, "Model actors require inference provenance.")
        }
        self.kind = kind
        self.identifier = normalizedIdentifier
        self.displayName = displayName
        self.inference = inference
    }

    /// Reconstructs attribution read from a durable adapter without trapping on legacy or future
    /// wire values. Persistence adapters should use this initializer instead of the checked
    /// programmatic initializer when their actor kind is stored as a raw string.
    public init(
        persistedKind rawKind: String,
        identifier: String? = nil,
        displayName: String? = nil,
        inference: InferenceProvenance? = nil
    ) {
        self = Self.reconstructed(
            rawKind: rawKind,
            identifier: identifier,
            displayName: displayName,
            inference: inference
        )
    }

    /// Stores already-degraded components without re-checking them.
    ///
    /// Exists solely for ``reconstructed(rawKind:identifier:displayName:inference:)``. The two read
    /// paths rebuild actors from values that outlived the process — persisted JSON and free `String`
    /// columns read back out of SwiftData — where the checked initializer's preconditions are the
    /// wrong tool: a row that violates one is a fact on disk, and trapping turns a bad row into a
    /// crash on the path that *reads history*. The degrade is applied first, then stored here.
    private init(
        degraded kind: ActorKind,
        identifier: String?,
        displayName: String?,
        inference: InferenceProvenance?
    ) {
        self.kind = kind
        self.identifier = identifier
        self.displayName = displayName
        self.inference = inference
    }

    /// Pinned wire format. Explicit so renaming a property can never silently change persisted JSON —
    /// the fixtures in `ActorAttributionTests` are the only other thing guarding this.
    private enum CodingKeys: String, CodingKey {
        case kind
        case identifier
        case displayName
        case inference
    }

    /// Identifier prefix marking an actor whose `kind` this build does not recognize.
    ///
    /// Namespaced deliberately: the degraded ref must not be able to alias a real `.workflow` actor
    /// and thereby pick up a capability lease that was never granted to it.
    static let unrecognizedKindIdentifierPrefix = "unrecognized-kind:"

    /// The degraded ref for an actor whose `kind` this build does not recognize.
    ///
    /// Shared by both tolerant paths — JSON ``init(from:)`` and the string bridge
    /// ``init(receiptActorDetail:)`` — because the mangling *is* the safety property: it must be
    /// impossible for one path to namespace the identifier and the other to pass it through, which
    /// would let an unknown-kind ref inherit a real workflow's `identityKey` and, with it, that
    /// workflow's capability lease.
    static func unrecognizedKind(
        _ rawKind: String,
        identifier: String?,
        displayName: String?,
        inference: InferenceProvenance?
    ) -> ActorRef {
        ActorRef(
            kind: .workflow,
            identifier: unrecognizedKindIdentifierPrefix + rawKind + (identifier.map { ":" + $0 } ?? ""),
            displayName: displayName ?? "Unrecognized actor (\(rawKind))",
            inference: inference
        )
    }

    /// The provenance stood in for a model actor whose own provenance did not survive the round trip.
    ///
    /// `.remote` rather than `.local`, for the reason ``InferenceProvenance/init(from:)`` degrades an
    /// unrecognized locality the same way: the value drives a user-facing privacy claim, and
    /// overstating that inputs left the device is harmless where the reverse is a false guarantee.
    /// `provider` stays `nil` because inventing one would put a fabricated name in front of a person.
    static let unattributedModelInference = InferenceProvenance(locality: .remote)

    /// Rebuilds an actor from components that outlived the process, degrading anything invalid
    /// instead of trapping.
    ///
    /// The single tolerant path, shared by JSON ``init(from:)`` and the string bridge
    /// ``init(receiptActorDetail:)``. Previously the two disagreed: `init(from:)` assigned the stored
    /// properties directly and so ran none of the checked initializer's preconditions — happily
    /// producing a `.model` actor with no provenance — while the bridge routed through the checked
    /// initializer and trapped on that same row. One read path silently violated the invariant and
    /// the other crashed on it. Routing both through here makes the `.model` ⇒ provenance invariant
    /// hold of values from either read path, which is what lets *that* precondition stay on for
    /// programmatic callers.
    ///
    /// The non-human ⇒ non-empty-identifier precondition is deliberately **not** reasserted here: a
    /// row violating it is a fact on disk, so this degrades instead of trapping, and values built by
    /// this path may carry a `nil` or `""` identifier the checked initializer would reject. Both are
    /// contained by ``identityKey``, which resolves them to `kind#anonymous` and `kind#id:` — keys no
    /// *named* actor can produce, so neither can pick up a grant made to a real one.
    ///
    /// Degrades, in order:
    /// - an unrecognized `kind`, folded onto a namespaced `.workflow` so it cannot inherit a real
    ///   workflow's lease;
    /// - a `.model` actor with no provenance, to ``unattributedModelInference``;
    /// - a non-human actor with no identifier, kept anonymous, because legacy rows written before the
    ///   field existed depend on still decoding. Such a ref aliases other identifier-less refs of the
    ///   same kind — which is why callers that must tell individuals apart (approval quorums) have to
    ///   supply identifiers; see ``identityKey``.
    static func reconstructed(
        rawKind: String,
        identifier: String?,
        displayName: String?,
        inference: InferenceProvenance?
    ) -> ActorRef {
        let normalizedIdentifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let known = ActorKind(rawValue: rawKind) else {
            return unrecognizedKind(
                rawKind,
                identifier: normalizedIdentifier,
                displayName: displayName,
                inference: inference
            )
        }
        return ActorRef(
            degraded: known,
            identifier: normalizedIdentifier,
            displayName: displayName,
            inference: known == .model ? (inference ?? unattributedModelInference) : inference
        )
    }

    /// Tolerant decoding for `kind`.
    ///
    /// Synthesized `Codable` throws on an unknown enum raw value, and every store that persists an
    /// actor reads its rows back through `compactMap` or `try?`. So a build encountering a seventh
    /// actor kind — written by a newer build, or by a future migration — would not read "unknown
    /// actor"; it would silently delete the entire worklog entry, lease, session, or run. Losing
    /// history is a strictly worse failure than an imprecise actor.
    ///
    /// The unknown kind is folded into the identifier rather than discarded, so the original value
    /// stays legible in the trace and the degraded ref cannot match a real workflow's identity.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = ActorRef.reconstructed(
            rawKind: try container.decode(String.self, forKey: .kind),
            identifier: try container.decodeIfPresent(String.self, forKey: .identifier),
            displayName: try container.decodeIfPresent(String.self, forKey: .displayName),
            inference: try container.decodeIfPresent(InferenceProvenance.self, forKey: .inference)
        )
    }
}

public extension ActorRef {
    /// The person using the app.
    static let human = ActorRef(kind: .human, identifier: "local-user")

    /// A non-attributed system/workflow actor. Convenience for internal, non-user-initiated work.
    static let system = ActorRef(kind: .workflow, identifier: "system")

    /// A model actor with the given inference provenance.
    static func model(identifier: String, inference: InferenceProvenance) -> ActorRef {
        ActorRef(kind: .model, identifier: identifier, displayName: nil, inference: inference)
    }

    /// A model actor for work performed on `route`.
    static func model(identifier: String, route: ModelRoute) -> ActorRef {
        model(identifier: identifier, inference: InferenceProvenance(route: route))
    }

    /// Stable identity for authority matching: kind + identifier only.
    ///
    /// Deliberately excludes `displayName` and `inference`, which are presentation and telemetry
    /// metadata. Structural equality would let a cosmetic difference decide whether a capability
    /// grant or denial applies — the same routine named once with a display name and once without
    /// must resolve to the same party.
    ///
    /// An identifier-less actor keys only by kind, because two such refs carry nothing that could
    /// tell them apart. Callers that need to distinguish individuals (collaborative approval quorums,
    /// for example) must supply identifiers. `nil` and `""` are kept distinct so an empty identifier
    /// can't silently alias the anonymous case.
    var identityKey: String {
        guard let identifier else { return "\(kind.rawValue)#anonymous" }
        return "\(kind.rawValue)#id:\(identifier)"
    }

    /// Whether this ref names the same party as `other`, ignoring display and inference metadata.
    func matchesIdentity(of other: ActorRef) -> Bool { identityKey == other.identityKey }

    /// A user-facing label naming *which* actor this is: the display name if it has one, else the
    /// identifier, else just the kind. Used by trust surfaces so a receipt reads "Morning Brief"
    /// rather than "system".
    ///
    /// Names the actor but does not say *what kind of party* it is, so it is the wrong thing to show
    /// alone on a surface where that is the question being asked. Prefer ``attributionLabel``.
    var displayLabel: String {
        bestAvailableName ?? kind.displayTitle
    }

    /// The full attribution for a trust surface: what kind of party this is, then which one.
    ///
    /// The kind is never dropped, and that is the whole point. A `displayName` is free-form metadata
    /// supplied by whoever constructed the ref, so rendering it alone let an automated routine named
    /// "Me" present itself to the person approving as `Actor: Me` — the one surface where confusing
    /// a routine for yourself changes the decision. Showing "Scheduled routine — Me" costs nothing
    /// and cannot mislead.
    ///
    /// Lives here rather than in a UI layer so the approval sheet, the receipt row, and the worklog
    /// entry for one action cannot drift apart; `ReceiptAttributionDisplay` renders stored receipts
    /// through the same format.
    var attributionLabel: String {
        guard let name = bestAvailableName else { return kind.displayTitle }
        return "\(kind.displayTitle) — \(name)"
    }

    /// The first *non-empty* of `displayName` then `identifier`.
    ///
    /// `displayName ?? identifier` was wrong: `??` short-circuits on a non-nil value, so a
    /// `displayName` of `""` discarded a perfectly good `identifier` and the ref rendered as a bare
    /// kind — dropping the "which one" half on the surfaces whose stated purpose is never to drop it.
    private var bestAvailableName: String? {
        [displayName, identifier]
            .compactMap { $0 }
            .first { !$0.isEmpty }
    }
}
