import Foundation

// Retroactive Sendable conformance for UserDefaults so test helpers can pass
// suite-scoped defaults across actor boundaries in this target. The shared
// AuralisTestSupport SPM package intentionally omits this conformance because
// it would otherwise leak into every consumer.
extension UserDefaults: @retroactive @unchecked Sendable {}
