import Foundation

/// A model's opinion on a run's *quality*, for the things deterministic criteria cannot reach.
///
/// A criterion can prove a brief was produced; nothing mechanical can say whether it was worth
/// reading. That gap is real, and this is the seam for closing it later with an on-device rubric
/// judge.
///
/// Deliberately a **second opinion, never a grade.** ``EvalResult/grade`` stays a pure function of
/// recorded evidence, for three reasons: model inference is nondeterministic, so folding it in would
/// make one run's grade unreproducible and two runs incomparable; it cannot execute in the fast CI
/// lane; and on-device inference currently fails on the simulator, which would turn every simulator
/// eval into a degraded result. A grade that a person may be held to should not depend on any of
/// that.
public protocol RubricJudging: Sendable {
    /// Scores a run against a prose rubric. Returns `nil` when no judgement is available — the model
    /// is unavailable, declined, or the spec carries no prose to judge against.
    func score(
        _ spec: OutcomeSpec,
        trace: [WorkflowStepLog]
    ) async -> RubricOpinion?
}

/// A model's advisory read on a run.
public struct RubricOpinion: Equatable, Sendable, Codable {
    /// 0…1, clamped on init. Advisory only.
    public let score: Double
    /// The model's stated reasoning, shown to a person rather than acted on.
    public let rationale: String
    /// Where inference ran, so a trust surface can say whether this left the device.
    public let provenance: InferenceProvenance

    public init(score: Double, rationale: String, provenance: InferenceProvenance) {
        // Clamped *and* checked for finiteness, because `min`/`max` do not reject NaN: every
        // comparison against NaN is false, so it survives both and lands in the stored property. That
        // matters more here than anywhere else in this package, because this value comes from a model
        // rather than from recorded evidence — a judge that divides by an empty rubric hands back NaN,
        // and a NaN score would make the enclosing ``EvalResult`` unequal to itself (defeating the
        // dedupe and round-trip guarantees the type is built on) and would throw on any JSON encode of
        // the graded run. A model opinion that cannot be represented is no opinion: it floors to 0,
        // which is advisory-only anyway and never touches the grade.
        self.score = score.isFinite ? min(max(score, 0), 1) : 0
        self.rationale = rationale
        self.provenance = provenance
    }

    /// Decodes *through* the clamping initializer above.
    ///
    /// Synthesized decoding would assign the stored score verbatim and skip the guard entirely, so a
    /// row written by a build whose judge emitted an out-of-range score would read back out of range
    /// and quietly violate the documented 0…1 contract. The normalization has to hold on the way in
    /// as well as at construction, or it is only a convention.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            score: try container.decode(Double.self, forKey: .score),
            rationale: try container.decode(String.self, forKey: .rationale),
            provenance: try container.decode(InferenceProvenance.self, forKey: .provenance)
        )
    }
}

/// The default: no model opinion at all.
///
/// This is what ships until a rubric judge is verified on physical hardware. It exists so the seam is
/// present and typed without any code path depending on inference — attaching a real judge later is
/// a composition change, not a redesign.
public struct NoRubricJudge: RubricJudging {
    public init() { }

    public func score(_ spec: OutcomeSpec, trace: [WorkflowStepLog]) async -> RubricOpinion? {
        nil
    }
}
