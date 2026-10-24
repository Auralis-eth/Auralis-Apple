import Foundation

/// Read/write surface for graded runs.
///
/// Results are stored rather than re-derived on read. Both are technically possible from a retained
/// worklog trace, but re-grading on every read would silently re-score historical runs under
/// whatever criteria are current — so editing a playbook's spec would rewrite its own track record,
/// and a report card could never be evidence of anything. A stored result is what the evidence said
/// at the time.
public protocol EvalResultStoring: Sendable {
    func record(_ result: EvalResult) async
    /// Every graded run, newest first.
    ///
    /// Deliberately unbounded, and this is the only read. `loadReportCards` groups results by the
    /// playbook their workflow belongs to, resolved through the execution records — so it needs
    /// every result, not a recent window: a graded run whose execution record has aged out must
    /// still contribute its grades, and bounding the fetch would silently drop them. The table is
    /// uncapped for the matching reason (a grade is evidence of what an operator did), so the cost
    /// here is accepted rather than engineered away.
    func allResults() async -> [EvalResult]
    /// Graded runs for one workflow. More than one is possible — a spec can be re-run against a
    /// retained trace — so this returns a list rather than an optional.
    func results(forCorrelationID correlationID: String) async -> [EvalResult]
    /// Erases all graded runs. Required rather than defaulted for the same reason
    /// `PerformanceStoring.resetAll()` is: a grade names what the person's operators did and how
    /// well, so a new store must not be able to quietly survive a privacy reset.
    func resetAll() async
}

/// In-memory results, for tests and for hosts with no durable container.
public actor InMemoryEvalResultStore: EvalResultStoring {
    private var results: [EvalResult] = []

    public init() { }

    public func record(_ result: EvalResult) {
        results.append(result)
    }

    public func allResults() -> [EvalResult] {
        results.sorted { $0.evaluatedAt > $1.evaluatedAt }
    }

    public func results(forCorrelationID correlationID: String) -> [EvalResult] {
        results
            .filter { $0.correlationID == correlationID }
            .sorted { $0.evaluatedAt > $1.evaluatedAt }
    }

    public func resetAll() {
        results.removeAll()
    }
}
