import Foundation
import SwiftUI

/// A trusted component for the `editDraft` request. Renders a resolved ``TrustedUIDraftSummary`` in an
/// editable field and returns the edited body through the supplied handler.
public struct DraftEditorCard: View {
    private let summary: TrustedUIDraftSummary
    private let onCommit: (String) -> Void
    @State private var buffer: DraftEditingBuffer

    public init(summary: TrustedUIDraftSummary, onCommit: @escaping (String) -> Void) {
        self.summary = summary
        self.onCommit = onCommit
        _buffer = State(initialValue: DraftEditingBuffer(summary))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summary.title)
                .font(.headline)
            TextEditor(text: $buffer.text)
                .frame(minHeight: 120)
                .padding(6)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("Draft content")
                .accessibilityIdentifier(TrustedUIA11yID.draftEditor)
            Button("Save draft") {
                onCommit(buffer.committedText(for: summary))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .frame(minHeight: 44)
            .accessibilityIdentifier(TrustedUIA11yID.draftSave)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .accessibilityElement(children: .contain)
        // `init` runs on every update, but the `State(initialValue:)` it builds is consulted only
        // the first time the view is installed at a structural position. On a later update carrying
        // a *different* draft into the same slot SwiftUI keeps the existing storage and throws the
        // new initial value away — so the editor held draft A's body beneath draft B's title, and
        // "Save draft" sent A's text to be stored under B's id.
        //
        // ``TrustedUIComponentRegistry/view(for:onApprovalDecision:onDraftCommit:onSuggestionAction:)``
        // now stamps `.id(draft.id)`, which makes that swap a fresh installation rather than an
        // update and is the structural fix. This re-sync covers the callers that build the card
        // directly, and keeps the card correct on its own rather than only inside the factory.
        .onChange(of: summary.id) { _, _ in
            buffer.retarget(to: summary)
        }
    }
}

/// The draft body being edited, carried together with the id of the draft it was loaded from.
///
/// Carrying the id is the whole point. ``DraftEditorCard`` holds this in `@State`, which SwiftUI
/// preserves across a change of `summary` whenever the card keeps its structural position — the same
/// swap ``ApprovalSubmissionGate`` exists to survive, and exactly what a queue does when it moves
/// the next draft into the slot the previous one vacated. A bare `String` cannot say whose text it
/// holds, so the card committed one draft's body under the next draft's id; the only guard on that
/// path, `draftResolver(id) != nil`, passes for both drafts and so catches nothing.
struct DraftEditingBuffer: Equatable {
    /// The draft `text` was loaded from, or last re-pointed at.
    private(set) var draftID: UUID

    /// The editable body. `var` because the editor binds straight to it.
    var text: String

    init(_ summary: TrustedUIDraftSummary) {
        self.draftID = summary.id
        self.text = summary.body
    }

    /// Points the buffer at `summary`, discarding edits that belong to a *different* draft.
    ///
    /// Edits to the same draft are kept: the caller fires this on every change of the rendered
    /// draft, and reloading the stored body when the id has not moved would silently throw away
    /// whatever the person had typed.
    mutating func retarget(to summary: TrustedUIDraftSummary) {
        guard draftID != summary.id else { return }
        self = DraftEditingBuffer(summary)
    }

    /// The text to commit for `summary` — never another draft's.
    ///
    /// Falls back to the stored body rather than refusing outright when the ids disagree: re-saving
    /// what is already stored is a no-op, whereas a "Save draft" button that silently does nothing
    /// is indistinguishable, on a trust surface, from one that saved.
    func committedText(for summary: TrustedUIDraftSummary) -> String {
        draftID == summary.id ? text : summary.body
    }
}

/// Shown by the registry when an id-referenced request cannot be resolved (e.g. a receipt or draft
/// that no longer exists). Fails visibly rather than rendering nothing.
public struct TrustedUIUnavailableCard: View {
    private let message: String

    public init(message: String) {
        self.message = message
    }

    public var body: some View {
        Label(message, systemImage: "questionmark.circle")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityIdentifier(TrustedUIA11yID.unavailable)
    }
}
