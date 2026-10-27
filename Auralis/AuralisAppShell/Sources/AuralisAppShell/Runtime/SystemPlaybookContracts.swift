import AuralisRuntime

/// The context contracts that govern playbooks (P0.5-402). Each playbook declares what context it
/// must be handed before it may run; ``SchedulingEngine`` enforces this against the bundle produced by
/// ``DefaultContextProvider`` and blocks the run on any violation.
///
/// Every playbook carries its own explicit, versioned declaration. The resolver reads that declaration
/// from the workflow value, so user-authored workflows remain executable without receiving an implicit
/// baseline that they never declared.
public enum SystemPlaybookContracts {
    /// Built-in declarations are registered eagerly; runtime-authored playbooks resolve the contract
    /// embedded in their own definition.
    public static let registry = ContextContractRegistry(
        declarations: SystemPlaybooks.all.map { playbook in
            ContextContractDeclaration(playbookID: playbook.id, contract: playbook.contextContract)
        },
        derived: { $0.contextContract }
    )

    /// The minimal contract for a playbook with no explicit declaration.
    ///
    /// Identical in substance to the built-in declarations — definition identity only, from
    /// `playbook.definition`, undeclared fields rejected — because
    /// ``DefaultContextProvider`` is playbook-agnostic and produces exactly those two fields for
    /// everything. So this is not a relaxation: a derived playbook is held to the same projection as a
    /// built-in one, and any future provider field stays invisible to it until something declares it.
    ///
    /// The identifier records *which* kind of declaration governed the run, so a contract named in
    /// history distinguishes "declared in the app binary" from "derived at runtime".
    public static func contract(
        for playbookID: String,
        identifier: String? = nil
    ) -> ContextBundleContract {
        ContextBundleContract(
            identifier: identifier ?? "system.playbook.\(playbookID)",
            requirements: [
                ContextFieldRequirement(
                    key: "playbook",
                    allowedDataClasses: [.publicIdentifier],
                    maxAge: 300,
                    authoritativeSource: .playbookDefinition,
                    missingFieldBehavior: .fail
                ),
                ContextFieldRequirement(
                    key: "playbook.name",
                    allowedDataClasses: [.publicIdentifier],
                    maxAge: 300,
                    authoritativeSource: .playbookDefinition,
                    missingFieldBehavior: .fail
                ),
                ContextFieldRequirement(
                    key: "playbook.source",
                    allowedDataClasses: [.derived],
                    maxAge: 300,
                    authoritativeSource: .playbookDefinition,
                    missingFieldBehavior: .fail
                ),
                ContextFieldRequirement(
                    key: "playbook.trigger",
                    allowedDataClasses: [.derived],
                    maxAge: 300,
                    authoritativeSource: .playbookDefinition,
                    missingFieldBehavior: .fail
                ),
                ContextFieldRequirement(
                    key: "playbook.flows",
                    allowedDataClasses: [.derived],
                    maxAge: 300,
                    authoritativeSource: .playbookDefinition,
                    missingFieldBehavior: .fail
                )
            ],
            missingFieldBehavior: .fail,
            additionalFieldBehavior: .reject
        )
    }
}
