import Foundation
import AuralisPrimaryModels
import SwiftData

public extension String {
    func withLeadingHashPrefix() -> String {
        hasPrefix("#") ? self : "#\(self)"
    }
}

public enum TagError: LocalizedError, Equatable {
    case emptyName
    case nameTooLong
    case invalidCharacters
    case duplicateName(existing: String)
    case invalidColor(color: String)
    case lowContrast
    case operationFailed(underlying: Error)
    case fetchFailed(underlying: Error)

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return NSLocalizedString("tag.error.emptyName", value: "Tag name cannot be empty", comment: "Error when tag name is empty")
        case .nameTooLong:
            return NSLocalizedString("tag.error.nameTooLong", value: "Tag name is too long (maximum 50 characters)", comment: "Error when tag name exceeds length limit")
        case .invalidCharacters:
            return NSLocalizedString("tag.error.invalidCharacters", value: "Tag name contains invalid characters", comment: "Error when tag name contains invalid characters")
        case .duplicateName(let existing):
            return NSLocalizedString("tag.error.duplicateName", value: "A tag named '\(existing)' already exists", comment: "Error when tag name already exists")
        case .invalidColor(let color):
            return NSLocalizedString("tag.error.invalidColor", value: "Invalid color format: \(color)", comment: "Error when color format is invalid")
        case .lowContrast:
            return NSLocalizedString("tag.error.lowContrast", value: "Color has insufficient contrast for accessibility", comment: "Error when color contrast is too low")
        case .operationFailed(let underlying):
            let format = NSLocalizedString("tag.error.operationFailed", value: "Operation failed: %@", comment: "Error shown when a tag operation fails for an underlying reason")
            return String(format: format, underlying.localizedDescription)
        case .fetchFailed(let underlying):
            let format = NSLocalizedString("tag.error.fetchFailed", value: "Failed to fetch tags: %@", comment: "Error shown when fetching tags fails for an underlying reason")
            return String(format: format, underlying.localizedDescription)
        }
    }

    public static func == (lhs: TagError, rhs: TagError) -> Bool {
        switch (lhs, rhs) {
        case (.emptyName, .emptyName),
            (.nameTooLong, .nameTooLong),
            (.invalidCharacters, .invalidCharacters),
            (.lowContrast, .lowContrast):
            return true
        case let (.duplicateName(lhsName), .duplicateName(rhsName)):
            return lhsName == rhsName
        case let (.invalidColor(lhsColor), .invalidColor(rhsColor)):
            return lhsColor == rhsColor
        case let (.operationFailed(lhsError), .operationFailed(rhsError)),
            let (.fetchFailed(lhsError), .fetchFailed(rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

public struct TagValue: Hashable, Codable, Sendable {
    public let name: String
    public let hexColor: String

    public init(name: String, hexColor: String) throws {
        self.name = try Tag.validateName(name)
        self.hexColor = try Tag.validateColor(hexColor)
    }
}

@Model
public final class Tag: Codable, Equatable, Hashable {
    @Attribute(.unique) public var name: String
    public var color: String
    public var createdAt: Date
    public var lastModified: Date
    public var nfts: [NFT] = []

    private static func isValidHexColor(_ color: String) -> Bool {
        guard color.hasPrefix("#") else { return false }
        let hex = String(color.dropFirst())
        guard hex.count == 3 || hex.count == 6 else { return false }
        return hex.allSatisfy { $0.isHexDigit }
    }

    public init(name: String, color: String = "#007AFF") throws {
        let validatedName = try Self.validateName(name)
        let validatedColor = try Self.validateColor(color)

        self.name = validatedName
        self.color = validatedColor
        let now = Date()
        self.createdAt = now
        self.lastModified = now
    }

    public func updateColor(_ newColor: String) -> Result<Void, TagError> {
        do {
            let validatedColor = try Self.validateColor(newColor)
            self.color = validatedColor
            self.lastModified = Date()
            return .success(())
        } catch let tagError as TagError {
            return .failure(tagError)
        } catch {
            return .failure(.invalidColor(color: newColor))
        }
    }

    public func updateName(_ newName: String) -> Result<Void, TagError> {
        do {
            let validatedName = try Self.validateName(newName)
            self.name = validatedName
            self.lastModified = Date()
            return .success(())
        } catch let tagError as TagError {
            return .failure(tagError)
        } catch {
            return .failure(.emptyName)
        }
    }

    public static func validateName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TagError.emptyName
        }
        guard trimmed.count <= 50 else {
            throw TagError.nameTooLong
        }
        return trimmed
    }

    public static func validateColor(_ color: String) throws -> String {
        let normalizedColor = color
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .withLeadingHashPrefix()

        guard isValidHexColor(normalizedColor) else {
            throw TagError.invalidColor(color: color)
        }
        return normalizedColor
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    public static func == (lhs: Tag, rhs: Tag) -> Bool {
        lhs.name == rhs.name
    }

    enum CodingKeys: String, CodingKey {
        case name, color, createdAt, lastModified
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.color = try container.decode(String.self, forKey: .color)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.lastModified = try container.decode(Date.self, forKey: .lastModified)
        self.nfts = []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(color, forKey: .color)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastModified, forKey: .lastModified)
    }
}
