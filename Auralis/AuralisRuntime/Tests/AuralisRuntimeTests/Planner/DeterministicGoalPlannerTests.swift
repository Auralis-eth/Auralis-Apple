import AuralisFoundation
@testable import AuralisRuntime
import Testing

struct DeterministicGoalPlannerTests {
    @Test("a recognized goal expands into its template's ordered steps")
    func recognizedGoalUsesTemplate() async {
        let planner = DeterministicGoalPlanner()
        let plan = await planner.makePlan(for: PlanningGoal(text: "Please organize my music library"))

        #expect(plan.capabilities == [.musicLibraryClassification, .autoOrganization, .autoOrganization])
        #expect(plan.steps.map(\.kind) == [.observe, .assist, .execute])
    }

    @Test("planning observes before it executes")
    func observeComesBeforeExecute() async {
        let planner = DeterministicGoalPlanner()
        let plan = await planner.makePlan(for: PlanningGoal(text: "make me a playlist of chill tracks"))

        let firstExecute = plan.steps.firstIndex { $0.kind == .execute }
        let firstObserve = plan.steps.firstIndex { $0.kind == .observe }
        #expect(firstObserve != nil)
        #expect(firstExecute != nil)
        #expect(firstObserve! < firstExecute!)
        #expect(plan.containsStateChange)
    }

    @Test("an unrecognized goal falls back to a single read-only step")
    func unrecognizedGoalIsObserveOnly() async {
        let planner = DeterministicGoalPlanner()
        let plan = await planner.makePlan(for: PlanningGoal(text: "xyzzy nonsense goal"))

        #expect(plan.steps.count == 1)
        #expect(plan.steps.first?.kind == .observe)
        #expect(plan.containsStateChange == false)
    }

    @Test("a recognized goal records the matched template as selected and the rest as rejected")
    func recordsDeliberationForMatchedGoal() async {
        let planner = DeterministicGoalPlanner()
        let plan = await planner.makePlan(for: PlanningGoal(text: "make me a playlist of chill tracks"))

        #expect(plan.deliberation.planner == "deterministic")
        #expect(plan.deliberation.selected.map(\.title) == ["make-playlist"])
        #expect(plan.deliberation.rejected.count == PlanTemplateCatalog.builtIn.count - 1)
        // Rejections say *why* they didn't fire.
        #expect(plan.deliberation.rejected.allSatisfy { $0.rationale.contains("did not mention") })
    }

    @Test("an unrecognized goal records a selected fallback and rejects every template")
    func recordsDeliberationForFallback() async {
        let planner = DeterministicGoalPlanner()
        let plan = await planner.makePlan(for: PlanningGoal(text: "xyzzy nonsense goal"))

        #expect(plan.deliberation.selected.map(\.title) == ["gather-context-fallback"])
        #expect(plan.deliberation.rejected.count == PlanTemplateCatalog.builtIn.count)
    }

    /// Keyword matching used to be `normalizedGoal.contains(keyword)`, and the `send-value`
    /// template's shortest keyword is `"tip"`. So an ordinary question about *tips* for tagging
    /// albums produced a plan whose second step signs a transaction — a wallet-signing plan from a
    /// music-library question. The keyword list is how this package decides whether a goal is about
    /// moving funds, so it has to match words, not fragments.
    @Test("a goal that merely contains a keyword as a fragment does not trigger its template")
    func substringKeywordDoesNotTriggerTemplate() async {
        let planner = DeterministicGoalPlanner()

        let plan = await planner.makePlan(for: PlanningGoal(text: "any tips for tagging my albums?"))

        #expect(plan.capabilities.contains(.signMessage) == false)
        #expect(plan.capabilities.contains(.draftTransaction) == false)
        #expect(plan.containsStateChange == false)
        #expect(plan.deliberation.selected.map(\.title) == ["gather-context-fallback"])
    }

    @Test("a goal that really is about sending value still triggers send-value")
    func wholeWordKeywordStillTriggersTemplate() async {
        let planner = DeterministicGoalPlanner()

        let plan = await planner.makePlan(for: PlanningGoal(text: "tip alice 5 eth please"))

        #expect(plan.deliberation.selected.map(\.title) == ["send-value"])
        #expect(plan.capabilities == [.draftTransaction, .signMessage])
    }

    /// Multi-word keywords have to keep working without reintroducing fragment matching.
    @Test("multi-word keywords match a run of whole words", arguments: [
        ("clean up my library", "organize-library"),
        ("sort my albums", "organize-library"),
        ("queue up a set for tonight", "make-playlist"),
        ("back up my library", "export-library")
    ])
    func multiWordKeywordsMatch(goal: String, expectedTemplate: String) async {
        let planner = DeterministicGoalPlanner()

        let plan = await planner.makePlan(for: PlanningGoal(text: goal))

        #expect(plan.deliberation.selected.map(\.title) == [expectedTemplate])
    }

    /// The fragment rule has to hold for *every* keyword in the catalog, not just `"tip"`.
    ///
    /// `"tip"` is the one that produced a wallet-signing plan from a music question, so it is the
    /// one that got a test — but `"pay"`, `"send"`, `"mix"`, and `"sort my"` are all short enough to
    /// sit inside ordinary English, and a future template adding another three-letter keyword gets
    /// no warning. Sweeping the catalog means the invariant is pinned to the rule, not to the one
    /// example that broke.
    @Test("no catalog keyword fires when it appears only as a fragment of a longer word")
    func noKeywordFiresAsAFragment() async {
        let planner = DeterministicGoalPlanner()

        for template in PlanTemplateCatalog.builtIn {
            for keyword in template.keywords {
                // Pad the *last* word so multi-word keywords are broken the same way single-word
                // ones are: "clean up" → "clean upzqx" is a fragment, not a run of whole words.
                var parts = keyword.split(separator: " ").map(String.init)
                guard let last = parts.popLast() else { continue }
                let fragmented = (parts + ["zqx\(last)zqx"]).joined(separator: " ")
                let plan = await planner.makePlan(for: PlanningGoal(text: fragmented))

                #expect(
                    plan.deliberation.selected.map(\.title) == ["gather-context-fallback"],
                    "“\(fragmented)” wrongly triggered a template via the keyword “\(keyword)”"
                )
                #expect(plan.containsStateChange == false, "fragment “\(fragmented)” planned a state change")
            }
        }
    }

    /// Every keyword must still fire on its own, so the word-boundary rewrite cannot quietly make a
    /// template unreachable — a template that never matches is a silent capability regression.
    @Test("every catalog keyword still triggers its own template when stated as whole words")
    func everyKeywordTriggersItsTemplate() async {
        let planner = DeterministicGoalPlanner()

        for (index, template) in PlanTemplateCatalog.builtIn.enumerated() {
            for keyword in template.keywords {
                let plan = await planner.makePlan(for: PlanningGoal(text: keyword))
                // An earlier template may legitimately claim the goal first; what must never happen
                // is the keyword matching nothing at all.
                let selected = plan.deliberation.selected.map(\.title)
                let acceptable = PlanTemplateCatalog.builtIn.prefix(index + 1).map(\.id)
                #expect(
                    selected.count == 1 && acceptable.contains(selected[0]),
                    "keyword “\(keyword)” of \(template.id) selected \(selected)"
                )
            }
        }
    }

    /// Matching is `first(where:)`, so a goal can match two templates and the later one loses on
    /// catalog order. The deliberation has to say *that*, because the surface exists to explain why
    /// an option was dropped — and "Goal did not mention any of: playlist, mix, …" is simply false
    /// about a goal that says "playlist". A rejection reason a reader can catch lying is worse than
    /// none.
    @Test("a template that matched but lost on precedence is not reported as a non-match")
    func precedenceLossIsReportedHonestly() async {
        let planner = DeterministicGoalPlanner()

        let plan = await planner.makePlan(for: PlanningGoal(text: "organize my playlist"))

        #expect(plan.deliberation.selected.map(\.title) == ["organize-library"])

        let playlist = plan.deliberation.rejected.first { $0.title == "make-playlist" }
        #expect(playlist != nil)
        #expect(playlist?.rationale.contains("did not mention") == false)
        #expect(playlist?.rationale.contains("took precedence") == true)
        #expect(playlist?.rationale.contains("organize-library") == true)

        // Templates that genuinely did not match keep the plain non-match reason.
        let sendValue = plan.deliberation.rejected.first { $0.title == "send-value" }
        #expect(sendValue?.rationale.contains("did not mention") == true)
    }

    /// `templates` is injectable, and selection used to key on `template.id`. Two templates sharing
    /// an id therefore both reported `isSelected`, so the deliberation claimed the planner chose two
    /// options while only the first template's steps were ever used.
    @Test("duplicate template ids still yield exactly one selected candidate")
    func duplicateTemplateIDsSelectOnlyOne() async {
        let step = PlanStep(capability: .audioPlayback, kind: .observe, title: "t", rationale: "r")
        let planner = DeterministicGoalPlanner(templates: [
            PlanTemplate(id: "dup", keywords: ["alpha"], summary: "first", steps: [step]),
            PlanTemplate(id: "dup", keywords: ["alpha"], summary: "second", steps: [step])
        ])

        let plan = await planner.makePlan(for: PlanningGoal(text: "alpha"))

        #expect(plan.summary == "first")
        #expect(plan.deliberation.selected.count == 1)
        #expect(plan.deliberation.rejected.count == 1)
    }

    @Test("templates only ever reference capabilities the registry knows")
    func templatesReferenceKnownCapabilities() {
        let known = Set(CapabilityID.allCases)
        for template in PlanTemplateCatalog.builtIn {
            for step in template.steps {
                #expect(known.contains(step.capability), "\(template.id) references unknown \(step.capability)")
            }
        }
    }
}
