import Foundation

/// The versioned shape of a persisted ``Artifact`` (P0.5-802).
///
/// An artifact is a durable work product — versioned, exported, and read back long after the build
/// that produced it — so the shape it was written under is a recorded fact, not an assumption about
/// the current build. This is what the `artifact.schema` deterministic check validates against.
public enum ArtifactSchema {
    /// The version this build writes.
    public static let currentVersion = 1

    /// Every version this build can read. An artifact outside this set cannot be interpreted, so the
    /// deterministic check fails closed on it rather than guessing.
    public static let supportedVersions: Set<Int> = [1]

    /// The version assumed for artifacts written before the column existed — the original field set.
    public static let legacyVersion = 1

    public static func supports(_ version: Int) -> Bool {
        supportedVersions.contains(version)
    }

    /// The largest body this build will accept, in characters.
    ///
    /// `Artifact.content` is external-storage-backed text; larger binary content is explicitly out of
    /// scope for v1 (see ``Artifact/content``). Bounding it in the schema means an operator that
    /// would produce an unbounded body is refused before it runs, instead of at the storage layer.
    public static let maximumContentLength = 1_000_000

    /// Returns human-readable problems with the artifact-shaping values a proposal declares, or an
    /// empty array when they satisfy this schema. Keys absent from `parameters` are not validated —
    /// a proposal that declares nothing about an artifact is the store's business, not the check's.
    public static func problems(inDeclared parameters: [String: String]) -> [String] {
        var problems: [String] = []
        if let rawType = parameters["artifactType"], ArtifactType(rawValue: rawType) == nil {
            let known = ArtifactType.allCases.map(\.rawValue).sorted().joined(separator: ", ")
            problems.append("artifactType “\(rawType)” is not one of: \(known)")
        }
        if let title = parameters["artifactTitle"], title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append("artifactTitle must not be blank")
        }
        if let content = parameters["artifactContent"], content.count > maximumContentLength {
            problems.append("artifactContent exceeds the \(maximumContentLength)-character limit")
        }
        return problems
    }

    /// Returns problems with an artifact's *actual* title and body, or an empty array when they
    /// satisfy this schema.
    ///
    /// ``problems(inDeclared:)`` validates what a proposal *claims* before it runs, which is the right
    /// guard for a proposal replayed from another build. But nothing in production declares a title or
    /// a body up front — both are composed *during* the run, and the body can come straight from a
    /// model response — so on the live path that function has nothing to validate and
    /// ``maximumContentLength`` binds nothing. This is the same contract applied at the boundary where
    /// the values exist, so the bound is enforced before an over-limit artifact is persisted.
    public static func problems(title: String, content: String) -> [String] {
        var problems: [String] = []
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append("artifactTitle must not be blank")
        }
        if content.count > maximumContentLength {
            problems.append("artifactContent exceeds the \(maximumContentLength)-character limit")
        }
        return problems
    }
}
