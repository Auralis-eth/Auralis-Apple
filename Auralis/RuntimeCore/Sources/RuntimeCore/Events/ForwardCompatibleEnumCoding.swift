/// The single key of a synthesized enum's wrapper object, read without knowing the case names.
///
/// Swift encodes an enum with associated values as a one-key object (`{"blocked":{"reason":"…"}}`).
/// Reading that key without a compile-time list of case names is what lets ``WorkflowWorklogEvent``
/// and ``WorkflowEvent`` fall back to an `unknown` case that carries the original payload verbatim,
/// rather than throwing and having the store's `compactMap`/`try?` delete the whole row (L-09).
struct SingleKeyEnumCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { nil }
}
