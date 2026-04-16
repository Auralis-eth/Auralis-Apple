import Foundation
import SwiftData
import SwiftUI
import UIKit

extension String {
    func withLeadingHashPrefix() -> String {
        hasPrefix("#") ? self : "#\(self)"
    }
}

extension Color {
    func toHexString() -> String {
        guard let components = self.cgColor?.components, components.count >= 3 else {
            return "#000000"
        }

        let red = UInt8(clamp(components[0] * 255))
        let green = UInt8(clamp(components[1] * 255))
        let blue = UInt8(clamp(components[2] * 255))
        let alpha: UInt8

        if components.count == 4 {
            alpha = UInt8(clamp(components[3] * 255))
        } else {
            alpha = 255
        }

        if alpha < 255 {
            return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
        } else {
            return String(format: "#%02X%02X%02X", red, green, blue)
        }
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        value < 0 ? 0 : (value > 255 ? 255 : value)
    }
}

extension UIColor {
    func contrastRatio(with color: UIColor) -> CGFloat {
        let luminance1 = self.luminance
        let luminance2 = color.luminance
        let lighter = max(luminance1, luminance2)
        let darker = min(luminance1, luminance2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private var luminance: CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0

        getRed(&red, green: &green, blue: &blue, alpha: nil)

        func adjustColorComponent(_ component: CGFloat) -> CGFloat {
            component <= 0.03928
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        let adjustedRed = adjustColorComponent(red)
        let adjustedGreen = adjustColorComponent(green)
        let adjustedBlue = adjustColorComponent(blue)

        return 0.2126 * adjustedRed + 0.7152 * adjustedGreen + 0.0722 * adjustedBlue
    }

    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0

        guard Scanner(string: hex).scanHexInt64(&int) else { return nil }

        let alpha: CGFloat = 1.0
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat

        switch hex.count {
        case 3:
            red = CGFloat((int >> 8) * 17) / 255
            green = CGFloat((int >> 4 & 0xF) * 17) / 255
            blue = CGFloat((int & 0xF) * 17) / 255
        case 6:
            red = CGFloat((int >> 16) & 0xFF) / 255
            green = CGFloat((int >> 8) & 0xFF) / 255
            blue = CGFloat(int & 0xFF) / 255
        default:
            return nil
        }

        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

enum TagError: LocalizedError, Equatable {
    case emptyName
    case nameTooLong
    case invalidCharacters
    case duplicateName(existing: String)
    case invalidColor(color: String)
    case lowContrast
    case operationFailed(underlying: Error)
    case fetchFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return NSLocalizedString(
                "tag.error.emptyName",
                value: "Tag name cannot be empty",
                comment: "Error when tag name is empty"
            )
        case .nameTooLong:
            return NSLocalizedString(
                "tag.error.nameTooLong",
                value: "Tag name is too long (maximum 50 characters)",
                comment: "Error when tag name exceeds length limit"
            )
        case .invalidCharacters:
            return NSLocalizedString(
                "tag.error.invalidCharacters",
                value: "Tag name contains invalid characters",
                comment: "Error when tag name contains invalid characters"
            )
        case .duplicateName(let existing):
            return NSLocalizedString(
                "tag.error.duplicateName",
                value: "A tag named '\(existing)' already exists",
                comment: "Error when tag name already exists"
            )
        case .invalidColor(let color):
            return NSLocalizedString(
                "tag.error.invalidColor",
                value: "Invalid color format: \(color)",
                comment: "Error when color format is invalid"
            )
        case .lowContrast:
            return NSLocalizedString(
                "tag.error.lowContrast",
                value: "Color has insufficient contrast for accessibility",
                comment: "Error when color contrast is too low"
            )
        case .operationFailed(let underlying):
            return "Operation failed: \(underlying.localizedDescription)"
        case .fetchFailed(let underlying):
            return "Failed to fetch tags: \(underlying.localizedDescription)"
        }
    }

    static func == (lhs: TagError, rhs: TagError) -> Bool {
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

@Model
class Tag: Codable, Equatable, Hashable {
    @Attribute(.unique) var name: String
    var color: String
    var createdAt: Date
    var lastModified: Date
    var nfts: [NFT] = []

    private static func isValidHexColor(_ color: String) -> Bool {
        guard color.hasPrefix("#") else { return false }
        let hex = String(color.dropFirst())
        guard hex.count == 3 || hex.count == 6 else { return false }
        return hex.allSatisfy { $0.isHexDigit }
    }

    init(name: String, color: String = "#007AFF") throws {
        let validatedName = try Self.validateName(name)
        let validatedColor = try Self.validateColor(color)

        self.name = validatedName
        self.color = validatedColor
        let now = Date()
        self.createdAt = now
        self.lastModified = now
    }

    func updateColor(_ newColor: String) -> Result<Void, TagError> {
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

    func updateName(_ newName: String) -> Result<Void, TagError> {
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

    static func validateName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TagError.emptyName
        }
        guard trimmed.count <= 50 else {
            throw TagError.nameTooLong
        }
        return trimmed
    }

    static func validateColor(_ color: String) throws -> String {
        let normalizedColor = color
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .withLeadingHashPrefix()

        guard isValidHexColor(normalizedColor) else {
            throw TagError.invalidColor(color: color)
        }
        return normalizedColor
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    static func == (lhs: Tag, rhs: Tag) -> Bool {
        lhs.name == rhs.name
    }

    enum CodingKeys: String, CodingKey {
        case name, color, createdAt, lastModified
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.color = try container.decode(String.self, forKey: .color)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.lastModified = try container.decode(Date.self, forKey: .lastModified)
        self.nfts = []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(color, forKey: .color)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastModified, forKey: .lastModified)
    }
}
