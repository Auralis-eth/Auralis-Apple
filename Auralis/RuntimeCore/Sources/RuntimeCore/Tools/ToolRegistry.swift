/// Central registry of runnable tools, resolved by ID.
///
/// Enforces the "tools cannot execute outside the registry" rule: the governed pipeline only runs a
/// tool it can resolve here, so an untrusted planner cannot conjure a tool that was never declared.
public actor ToolRegistry {
    private var tools: [String: ToolDefinition] = [:]

    @_spi(ToolRegistration)
    public init() { }

    /// Registers a definition once. Re-registering the identical definition is idempotent, while a
    /// conflicting definition is rejected so bootstrap order cannot silently change governance.
    @_spi(ToolRegistration)
    @discardableResult
    public func register(_ tool: ToolDefinition) -> ToolRegistrationResult {
        let problems = tool.definitionProblems
        guard problems.isEmpty else {
            return .invalid(problems: problems)
        }
        guard let existing = tools[tool.id] else {
            tools[tool.id] = tool
            return .registered
        }
        return existing == tool ? .alreadyRegistered : .conflict(existing: existing)
    }

    public func tool(id: String) -> ToolDefinition? {
        tools[id]
    }

    public var allTools: [ToolDefinition] {
        Array(tools.values)
    }
}

public enum ToolRegistrationResult: Equatable, Sendable {
    case registered
    case alreadyRegistered
    case conflict(existing: ToolDefinition)
    case invalid(problems: [String])

    public var succeeded: Bool {
        switch self {
        case .registered, .alreadyRegistered: true
        case .conflict, .invalid: false
        }
    }
}
