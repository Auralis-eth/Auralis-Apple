// Re-exports the governed-runtime kernel through `AuralisAppShell`.
//
// `RuntimeHost`'s public surface is expressed almost entirely in AuralisRuntime's vocabulary: it takes
// `ActorRef` and `ReceiptDraft`, returns `ToolCallOutcome` and `CapabilityLease`, and vends the
// registries and event bus directly. A consumer therefore cannot use this package meaningfully
// without those types in scope, so re-exporting them means `import AuralisAppShell` is sufficient rather
// than being one half of an import pair that is useless on its own.
//
// The cost is that `@_exported` is an underscored attribute: unofficial, unsupported, and free to
// change between compiler releases. That is a real risk and it is accepted deliberately rather than
// overlooked. The mitigation is that nothing depends on the *mechanism* — if the attribute stops
// working, the fix is to add `import AuralisRuntime` to the nine app-side files that currently rely on
// this (Mission Control's goal view, the runtime/policy assemblies, the background scheduler, the
// privacy reset, and the ritual/social adapters). That is a mechanical change with no design
// consequences, which is what makes the risk affordable.
//
// Deliberately only AuralisRuntime. The other fourteen dependencies stay private: a consumer that wants
// `AuralisRuntime` or `AuralisOperators` types names them itself, so this does not become a way for the
// package's whole dependency graph to leak into every file that imports it.
@_exported import AuralisRuntime
