import CryptoKit
import Foundation

/// What a workflow does when a required field is missing or stale.
public enum MissingFieldBehavior: String, Codable, Sendable {
    /// Refuse to run.
    case fail
    /// Accept a stale value if one is present.
    case useStale
    /// Run without the field.
    case proceedWithoutField
}

/// How fields that were not declared by the workflow contract are handled.
public enum AdditionalFieldBehavior: String, Codable, Sendable {
    /// Refuse the bundle. This is the safe default for governed workflows.
    case reject
    /// Drop undeclared fields from the context handed to the workflow.
    case omit
}

/// A workflow's declared requirement for a single context field.
public struct ContextFieldRequirement: Codable, Equatable, Sendable {
    public let key: String
    public let isRequired: Bool
    public let allowedDataClasses: [ContextDataClass]
    /// Maximum age, in seconds, before the field is considered stale. Always bounded — every
    /// declared field carries a freshness window, and a negative value is a contract configuration
    /// violation rather than a way to opt out.
    public let maxAge: TimeInterval
    public let authoritativeSource: GovernedContextSource
    /// Overrides the contract-wide behavior for this field.
    public let missingFieldBehavior: MissingFieldBehavior?

    public init(
        key: String,
        isRequired: Bool = true,
        allowedDataClasses: [ContextDataClass],
        maxAge: TimeInterval,
        authoritativeSource: GovernedContextSource,
        missingFieldBehavior: MissingFieldBehavior
    ) {
        self.key = key
        self.isRequired = isRequired
        self.allowedDataClasses = allowedDataClasses
        self.maxAge = maxAge
        self.authoritativeSource = authoritativeSource
        self.missingFieldBehavior = missingFieldBehavior
    }
}

/// The result of validating a ``ContextBundle`` against a ``ContextBundleContract``.
public struct ContextContractValidation: Codable, Equatable, Sendable {
    public let isSatisfied: Bool
    public let violations: [String]
    /// The only fields a workflow is allowed to observe. Undeclared and omitted fields never appear.
    public let approvedBundle: ContextBundle

    public init(isSatisfied: Bool, violations: [String], approvedBundle: ContextBundle) {
        self.isSatisfied = isSatisfied
        self.violations = violations
        self.approvedBundle = approvedBundle
    }
}

/// A workflow's declaration of the context it needs: required fields, allowed data classes,
/// freshness bounds, authoritative sources, and what to do when something is missing.
///
/// This is where Auralis stops being "AI with context" and becomes "governed operating context":
/// a bundle can be checked against the contract *before* a workflow ever sees the data.
public struct ContextBundleContract: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public let identifier: String
    public let schemaVersion: Int
    public let requirements: [ContextFieldRequirement]
    public let missingFieldBehavior: MissingFieldBehavior
    public let additionalFieldBehavior: AdditionalFieldBehavior
    /// Maximum tolerated amount by which a source timestamp may be ahead of the validation clock.
    public let maximumFutureSkew: TimeInterval

    public init(
        identifier: String = "context.contract",
        schemaVersion: Int = Self.currentSchemaVersion,
        requirements: [ContextFieldRequirement],
        missingFieldBehavior: MissingFieldBehavior = .fail,
        additionalFieldBehavior: AdditionalFieldBehavior = .reject,
        maximumFutureSkew: TimeInterval = 300
    ) {
        self.identifier = identifier
        self.schemaVersion = schemaVersion
        self.requirements = requirements
        self.missingFieldBehavior = missingFieldBehavior
        self.additionalFieldBehavior = additionalFieldBehavior
        self.maximumFutureSkew = maximumFutureSkew
    }

    private enum CodingKeys: String, CodingKey {
        case identifier
        case schemaVersion
        case requirements
        case missingFieldBehavior
        case additionalFieldBehavior
        case maximumFutureSkew
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try container.decodeIfPresent(String.self, forKey: .identifier) ?? "legacy.context.contract"
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        requirements = try container.decode([ContextFieldRequirement].self, forKey: .requirements)
        missingFieldBehavior = try container.decodeIfPresent(
            MissingFieldBehavior.self,
            forKey: .missingFieldBehavior
        ) ?? .fail
        additionalFieldBehavior = try container.decodeIfPresent(
            AdditionalFieldBehavior.self,
            forKey: .additionalFieldBehavior
        ) ?? .reject
        maximumFutureSkew = try container.decodeIfPresent(TimeInterval.self, forKey: .maximumFutureSkew) ?? 300
    }

    /// Validates a bundle against this contract as of `now`.
    public func validate(_ bundle: ContextBundle, now: Date = .now) -> ContextContractValidation {
        var violations = configurationViolations() + bundle.sizeViolations()
        var approvedFields: [ContextField] = []

        if bundle.schemaVersion != ContextBundle.currentSchemaVersion {
            violations.append("unsupported bundle schema version \(bundle.schemaVersion)")
        }

        let requirementKeys = requirements.map(\.key)

        let bundleKeys = bundle.fields.map(\.key)
        let duplicateBundleKeys = duplicateKeys(in: bundleKeys)
        for key in duplicateBundleKeys {
            violations.append("bundle contains duplicate field “\(key)”")
        }

        let declaredKeys = Set(requirementKeys)
        if additionalFieldBehavior == .reject {
            for key in Set(bundleKeys).subtracting(declaredKeys).sorted() {
                violations.append("bundle contains undeclared field “\(key)”")
            }
        }

        for requirement in requirements {
            if requirement.key.isEmpty
                || requirement.allowedDataClasses.isEmpty
                || requirement.maxAge < 0 {
                continue
            }

            let behavior = requirement.missingFieldBehavior ?? missingFieldBehavior
            guard let field = bundle.field(requirement.key), field.stringValue != nil else {
                if requirement.isRequired, behavior != .proceedWithoutField {
                    violations.append("missing required field “\(requirement.key)”")
                }
                continue
            }

            var fieldIsApproved = true
            if field.dataClass == .sensitive {
                if case .sensitiveReference = field.value {
                    // The value is an opaque vault handle; raw sensitive bytes are not representable.
                } else {
                    violations.append("field “\(requirement.key)” does not contain a safe sensitive reference")
                    fieldIsApproved = false
                }
            }
            if !requirement.allowedDataClasses.contains(field.dataClass) {
                violations.append(
                    "field “\(requirement.key)” has disallowed data class \(field.dataClass.rawValue)"
                )
                fieldIsApproved = false
            }

            if field.source != requirement.authoritativeSource {
                violations.append(
                    "field “\(requirement.key)” came from \(field.source?.rawValue ?? "unknown"), expected \(requirement.authoritativeSource.rawValue)"
                )
                fieldIsApproved = false
            }

            let maxAge = requirement.maxAge
            let refreshed = field.lastRefreshed
            let age = refreshed.map { now.timeIntervalSince($0) }
            if let age, age < -maximumFutureSkew {
                violations.append("field “\(requirement.key)” has a future refresh timestamp")
                fieldIsApproved = false
            } else if age.map({ $0 > maxAge }) ?? true {
                switch behavior {
                case .fail:
                    violations.append("field “\(requirement.key)” is stale")
                    fieldIsApproved = false
                case .useStale:
                    break
                case .proceedWithoutField:
                    fieldIsApproved = false
                }
            }

            if fieldIsApproved, !duplicateBundleKeys.contains(requirement.key) {
                approvedFields.append(field)
            }
        }

        return ContextContractValidation(
            isSatisfied: violations.isEmpty,
            violations: violations,
            approvedBundle: ContextBundle(schemaVersion: bundle.schemaVersion, fields: approvedFields)
        )
    }

    /// Validates the declaration itself before it is registered or receives any runtime data.
    public func configurationViolations() -> [String] {
        var violations: [String] = []
        if identifier.isEmpty { violations.append("contract identifier is empty") }
        if schemaVersion != Self.currentSchemaVersion {
            violations.append("unsupported contract schema version \(schemaVersion)")
        }
        if maximumFutureSkew < 0 { violations.append("maximum future skew cannot be negative") }

        for key in duplicateKeys(in: requirements.map(\.key)) {
            violations.append("contract declares field “\(key)” more than once")
        }
        for requirement in requirements {
            if requirement.key.isEmpty {
                violations.append("contract contains an empty field key")
            }
            if requirement.allowedDataClasses.isEmpty {
                violations.append("field “\(requirement.key)” has no allowed data classes")
            }
            if requirement.maxAge < 0 {
                violations.append("field “\(requirement.key)” has a negative maximum age")
            }
        }
        return violations
    }

    /// Stable, value-free fingerprint of the declaration enforced for a run.
    public func evidenceDigest() -> String {
        let manifest = requirements.map {
            let classes = $0.allowedDataClasses.map(\.rawValue).sorted().joined(separator: ",")
            return "\($0.key)|\($0.isRequired)|\(classes)|\($0.maxAge)|\($0.authoritativeSource.rawValue)|\(($0.missingFieldBehavior ?? missingFieldBehavior).rawValue)"
        }
        .sorted()
        .joined(separator: "\n")
        let declaration = "\(identifier)|\(schemaVersion)|\(additionalFieldBehavior.rawValue)|\(maximumFutureSkew)\n\(manifest)"
        return SHA256.hash(data: Data(declaration.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func duplicateKeys(in keys: [String]) -> [String] {
        var seen: Set<String> = []
        var duplicates: Set<String> = []
        for key in keys where !seen.insert(key).inserted {
            duplicates.insert(key)
        }
        return duplicates.sorted()
    }
}

public extension ContextBundleContract {
    /// An explicit declaration that a workflow consumes no contextual fields.
    static func noContext(identifier: String) -> ContextBundleContract {
        ContextBundleContract(identifier: identifier, requirements: [])
    }
}
