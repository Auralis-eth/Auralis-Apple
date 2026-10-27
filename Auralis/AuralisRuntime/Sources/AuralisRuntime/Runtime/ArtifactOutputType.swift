/// The portable kind of work product a runtime workflow may request.
///
/// The runtime owns this declaration because playbooks must describe their allowed outputs without
/// depending outward on the receipt/artifact persistence domain.
public enum ArtifactOutputType: String, Codable, CaseIterable, Sendable {
    case doc
    case brief
    case report
    case jsonExport
    case codeFile
    case planChecklist
}
