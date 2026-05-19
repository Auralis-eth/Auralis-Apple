public enum ExternalLinkAuditRequirement: Equatable, Sendable {
    case durable
    case bestEffort

    public var requiresDurableAudit: Bool {
        self == .durable
    }
}
