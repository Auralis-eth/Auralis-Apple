import Foundation

/// Identifiers for the record-shape deterministic checks (P0.5-802).
///
/// The identifiers live here while the checks themselves live in `RuntimeKit`, because a check ID is
/// just a string but validating a receipt or artifact schema requires *seeing* those schemas — and
/// both `ArtifactCore` and `OperatorsFeature` sit between this package and them. Tools that produce
/// records need to name these checks; only the runtime host needs to implement them.
public enum RecordSchemaCheckID {
    public static let receiptSchema = "receipt.schema"
    public static let artifactSchema = "artifact.schema"
}

/// The parameter keys a proposal declares its record shapes under.
///
/// Governance metadata the host stamps onto every proposal it builds, rather than operation
/// parameters the actor asked for — surfaces that render "what this run will operate on" exclude
/// ``all``.
public enum RecordSchemaKey {
    public static let artifactVersion = "artifactSchemaVersion"
    public static let artifactType = "artifactType"

    public static let all: Set<String> = [artifactVersion, artifactType]
}
