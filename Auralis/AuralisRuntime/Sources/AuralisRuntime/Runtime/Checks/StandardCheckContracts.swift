/// Stable identifiers shared by the runtime pipeline and the concrete check adapters that register
/// against it. The identifiers are contracts; crypto validation implementations live outside the
/// generic runtime package.
public enum StandardCheckID {
    public static let addressFormat = "address.format"
    public static let ensNameFormat = "ens.format"
    public static let chainInScope = "chain.inScope"
    public static let contextFresh = "context.fresh"
}

public enum StandardCheckParameterKey {
    public static let contextRefreshedAt = "contextRefreshedAt"
    public static let freshnessEvaluatedAt = "freshnessEvaluatedAt"
}
