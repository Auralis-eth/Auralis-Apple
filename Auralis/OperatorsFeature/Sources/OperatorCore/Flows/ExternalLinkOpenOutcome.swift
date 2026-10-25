public enum ExternalLinkOpenOutcome: Equatable, Sendable {
    case opened
    case openedWithAuditWarning
    case blockedMissingAudit
}
