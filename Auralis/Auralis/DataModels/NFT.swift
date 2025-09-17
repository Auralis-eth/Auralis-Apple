//
//  NFT.swift
//  Auralis
//
//  Created by Daniel Bell on 1/6/25.
//

import Foundation
import SwiftData
import web3
import UIKit

// MARK: - Helper Functions & Computed Properties
enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let dbl = try? container.decode(Double.self) {
            self = .double(dbl)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                DecodingError.Context(codingPath: decoder.codingPath,
                                      debugDescription: "Unsupported JSON type")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let dict):
            try container.encode(dict)
        case .array(let array):
            try container.encode(array)
        }
    }

    var stringValue: String? {
        switch self {
            case .string(let value):
                return value
            default:
                return nil
        }
    }

    var objectValue: [String: JSONValue]? {
        switch self {
            case .object(let value):
                return value
            default:
                return nil
        }
    }

    var intValue: Int? {
        switch self {
            case .int(let value):
                return value
            default:
                return nil
        }
    }

    var doubleValue: Double? {
        switch self {
            case .double(let value):
                return value
            default:
                return nil
        }
    }

    var arrayValue: [JSONValue]? {
        switch self {
            case .array(let value):
                return value
            default:
                return nil
        }
    }
}

import SwiftUI
import SwiftUI
import SwiftData

// MARK: - Updated TagMutatingView
struct TagMutatingView: View {
    @Query(sort: [SortDescriptor(\Tag.name)]) private var tags: [Tag]
    
    @State private var lastError: TagError?
    @State private var showingCreateSheet = false
    @State private var tagToUpdate: Tag?
    
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(tags) { tag in
                        VStack(spacing: 8) {
                            Text(tag.name)
                                .font(.headline)
                                .foregroundStyle(tag.color.toColor())
                            
                            HStack(spacing: 16) {
                                Button {
                                    deleteTag(tag)
                                } label: {
                                    Text("Delete")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.glass)
                                
                                Button {
                                    tagToUpdate = tag
                                } label: {
                                    Text("Update")
                                }
                                .buttonStyle(.glass)
                            }
                        }
                        .padding()
                        .glassEffect(.clear.interactive(), in: .rect)
                    }
                }
                .padding()
            }
            .navigationTitle("Tags")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                TagCreateUpdateView()
            }
            .sheet(item: $tagToUpdate) { tag in
                TagCreateUpdateView(existingTag: tag)
            }
            .alert("Error", isPresented: .constant(lastError != nil)) {
                Button("OK") {
                    lastError = nil
                }
            } message: {
                if let error = lastError {
                    Text(error.localizedDescription)
                }
            }
        }
    }
    
    private func deleteTag(_ tag: Tag) {
        lastError = nil
        do {
            modelContext.delete(tag)
            try modelContext.save()
        } catch {
            lastError = TagError.operationFailed(underlying: error)
        }
    }
}

// MARK: - TagCreateUpdateView
struct TagCreateUpdateView: View {
    @Query(sort: [SortDescriptor(\Tag.name)]) private var tags: [Tag]
    @Environment(\.modelContext) private var modelContext
    
    @State private var existingTag: Tag?
    @State private var tagName: String
    @State private var tagColor: String
    @State private var validationError: TagError?
    
    @Environment(\.dismiss) private var dismiss
    
    // Predefined color options
    private let colorOptions = [
        ("Red", "FF0000"),
        ("Green", "00FF00"),
        ("Blue", "0000FF"),
        ("Orange", "FF8800"),
        ("Purple", "8800FF"),
        ("Pink", "FF0088"),
        ("Cyan", "00FFFF"),
        ("Yellow", "FFFF00"),
        ("Indigo", "4B0082"),
        ("Teal", "008080")
    ]
    
    @State private var selectedColorIndex: Int = 0
    @State private var useCustomColor = false
    
    private enum Constants {
        static let maxNameLength = 50
        static let allowedCharacterSet = CharacterSet.letters
            .union(.decimalDigits)
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: "-_.,!?()&"))
    }
    
    init(existingTag: Tag? = nil) {
        self.existingTag = existingTag
        
        if let existingTag = existingTag {
            _tagName = State(initialValue: existingTag.name)
            _tagColor = State(initialValue: existingTag.color)
            
            // Find matching color in options
            if let index = colorOptions.firstIndex(where: { $0.1 == existingTag.color }) {
                _selectedColorIndex = State(initialValue: index)
                _useCustomColor = State(initialValue: false)
            } else {
                _useCustomColor = State(initialValue: true)
            }
        } else {
            _tagName = State(initialValue: "")
            _tagColor = State(initialValue: colorOptions[0].1)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Tag Details") {
                    TextField("Tag Name", text: $tagName)
                        .textFieldStyle(.roundedBorder)
                }
                
                Section("Color") {
                    Toggle("Use Custom Color", isOn: $useCustomColor)
                    
                    if useCustomColor {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Hex Color (e.g., FF0000)", text: $tagColor)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.allCharacters)
                            
                            HStack {
                                Text("Preview:")
                                Circle()
                                    .fill(tagColor.toColor())
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.gray, lineWidth: 1)
                                    )
                            }
                        }
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                            ForEach(0..<colorOptions.count, id: \.self) { index in
                                let (colorName, colorHex) = colorOptions[index]
                                
                                Button {
                                    selectedColorIndex = index
                                    tagColor = colorHex
                                } label: {
                                    Circle()
                                        .fill(colorHex.toColor())
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    selectedColorIndex == index ? Color.primary : Color.gray,
                                                    lineWidth: selectedColorIndex == index ? 3 : 1
                                                )
                                        )
                                }
                                .accessibilityLabel(colorName)
                            }
                        }
                    }
                }
                
                if let validationError = validationError?.errorDescription {
                    Section {
                        Text(validationError)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(existingTag == nil ? "Create Tag" : "Update Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(existingTag == nil ? "Create" : "Update") {
                        saveTag()
                    }
                    .disabled(!isFormValid)
                }
            }
        }
    }
    
    private var isFormValid: Bool {
        (try? validateForm()) ?? false
    }
    
    private func validateForm() throws -> Bool {
        // Validate name
        let trimmedName = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedName.isEmpty {
            throw TagError.emptyName
        }
        
        if trimmedName.count > Constants.maxNameLength {
            throw TagError.nameTooLong
        }
        
        // Check for invalid characters
        if trimmedName.rangeOfCharacter(from: Constants.allowedCharacterSet.inverted) != nil {
            throw TagError.invalidCharacters
        }
        
        // Check for duplicate names (excluding current tag being updated)
        let lowercasedName = trimmedName.lowercased()
        if Set(tags.map { $0.name.lowercased() }).contains(lowercasedName) &&
           existingTag?.name.lowercased() != lowercasedName {
            throw TagError.duplicateName(existing: lowercasedName)
        }
        
        // Validate color
        let trimmedColor = tagColor.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedColor.isEmpty {
            throw TagError.invalidColor(color: trimmedColor)
        }
        
        // Validate hex color format
        let cleanColor = trimmedColor.replacingOccurrences(of: "#", with: "")
        if !(cleanColor.count == 6 || cleanColor.count == 8) {
            throw TagError.invalidColor(color: cleanColor)
        }
        
        let hexCharacterSet = CharacterSet(charactersIn: "0123456789ABCDEFabcdef")
        if cleanColor.rangeOfCharacter(from: hexCharacterSet.inverted) != nil {
            throw TagError.invalidColor(color: cleanColor)
        }
        
        return true
    }
    
    private func saveTag() {
        do {
            guard try validateForm() else {
                return
            }
        } catch let error as TagError {
            validationError = error
        } catch {
            let tagError = TagError.operationFailed(underlying: error)
            validationError = tagError
        }
        
        validationError = nil
        
        let trimmedName = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanColor = tagColor.replacingOccurrences(of: "#", with: "").uppercased()
        
        if existingTag != nil {
            updateTag(name: trimmedName, color: cleanColor)
        } else {
            createTag(name: trimmedName, color: cleanColor)
        }
        
        dismiss()
    }
    
    
    private func processAndValidateTagName(_ name: String, excludingTag: Tag? = nil) throws -> String {
        let cleanedString = name.components(separatedBy: .controlCharacters).joined()
        let normalizedString = cleanedString
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let trimmed = normalizedString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else { throw TagError.emptyName }
        guard trimmed.count <= Constants.maxNameLength else { throw TagError.nameTooLong }
        guard trimmed.rangeOfCharacter(from: Constants.allowedCharacterSet.inverted) == nil else {
            throw TagError.invalidCharacters
        }
        
        try validateUniqueTag(name: trimmed, excludingTag: excludingTag)
        return trimmed
    }
    
    private func validateUniqueTag(name: String, excludingTag: Tag? = nil) throws {
        let lowerName = name.lowercased()
        
        if let excluding = excludingTag, excluding.name.lowercased() == lowerName {
            return
        }
        
        if Set(tags.map { $0.name.lowercased() }).contains(lowerName) {
            throw TagError.duplicateName(existing: lowerName)
        }
    }
    
    /// Enhanced color validation with accessibility check
    private func validateColor(_ color: String) throws -> String {
        let validated = try Tag.validateColor(color)
        
        // Accessibility check using WCAG contrast guidelines
        if let uiColor = UIColor(hex: validated) {
            let contrastRatio = uiColor.contrastRatio(with: .white)
            if contrastRatio < 4.5 {
                throw TagError.lowContrast
            }
        }
        
        return validated
    }
    
    private func createTag(name: String, color: String) {
        validationError = nil
        
        do {
            let validatedName = try self.processAndValidateTagName(name)
            let validatedColor = try self.validateColor(color)
            
            let tag = try Tag(name: validatedName, color: validatedColor)
            
            self.modelContext.insert(tag)
            try self.modelContext.save()
        } catch let error as TagError {
            validationError = error
        } catch {
            let tagError = TagError.operationFailed(underlying: error)
            validationError = tagError
        }

    }
    
    private func updateTag(name: String, color: String) {
        validationError = nil
        
        guard let tag = existingTag else {
            return
        }
        do {
            // Use Tag model's update methods
            let nameResult = tag.updateName(name)
            let colorResult = tag.updateColor(color)
            
            // Handle validation results from Tag model
            try nameResult.get()
            try colorResult.get()
            
            try self.modelContext.save()
        } catch let error as TagError {
            validationError = error
        } catch {
            let tagError = TagError.operationFailed(underlying: error)
            validationError = tagError
        }
    }
}

import SwiftUI

struct ColorPickerWithHex: View {
    @State private var selectedColor = Color.blue
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Color Picker")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Color preview rectangle
            RoundedRectangle(cornerRadius: 12)
                .fill(selectedColor)
                .frame(width: 200, height: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray, lineWidth: 1)
                )
            
            // ColorPicker
            ColorPicker("Select Color", selection: $selectedColor)
                .frame(maxWidth: 300)
            
            // Hex value display
            VStack(alignment: .leading, spacing: 8) {
                Text("Hex Value:")
                    .font(.headline)
                
                Text(selectedColor.toHexString())
                    .font(.system(.title2, design: .monospaced))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .textSelection(.enabled) // Allows text selection for copying
            }
        }
        .padding()
    }
}

// Optimized Color extension for hex conversion
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
        
        // Include alpha only if it's not fully opaque
        if alpha < 255 {
            return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
        } else {
            return String(format: "#%02X%02X%02X", red, green, blue)
        }
    }
    
    private func clamp(_ value: CGFloat) -> CGFloat {
        return value < 0 ? 0 : (value > 255 ? 255 : value)
    }
}

//---------------------------------------------------
// MARK: - UIColor Extension for Accessibility

extension UIColor {
    /// Calculate contrast ratio according to WCAG guidelines
    func contrastRatio(with color: UIColor) -> CGFloat {
        let luminance1 = self.luminance
        let luminance2 = color.luminance
        let lighter = max(luminance1, luminance2)
        let darker = min(luminance1, luminance2)
        return (lighter + 0.05) / (darker + 0.05)
    }
    
    /// Calculate relative luminance according to WCAG formula
    private var luminance: CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        
        getRed(&red, green: &green, blue: &blue, alpha: nil)
        
        func adjustColorComponent(_ component: CGFloat) -> CGFloat {
            return component <= 0.03928
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }
        
        let adjustedRed = adjustColorComponent(red)
        let adjustedGreen = adjustColorComponent(green)
        let adjustedBlue = adjustColorComponent(blue)
        
        return 0.2126 * adjustedRed + 0.7152 * adjustedGreen + 0.0722 * adjustedBlue
    }
    
    /// Initialize UIColor from hex string
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        
        guard Scanner(string: hex).scanHexInt64(&int) else { return nil }
        
        let alpha: CGFloat = 1.0
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        
        switch hex.count {
        case 3: // RGB (12-bit)
            red = CGFloat((int >> 8) * 17) / 255
            green = CGFloat((int >> 4 & 0xF) * 17) / 255
            blue = CGFloat((int & 0xF) * 17) / 255
        case 6: // RGB (24-bit)
            red = CGFloat((int >> 16) & 0xFF) / 255
            green = CGFloat((int >> 8) & 0xFF) / 255
            blue = CGFloat(int & 0xFF) / 255
        default:
            return nil
        }
        
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

// MARK: - Localized Error Types

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
            return NSLocalizedString("tag.error.emptyName",
                                   value: "Tag name cannot be empty",
                                   comment: "Error when tag name is empty")
        case .nameTooLong:
            return NSLocalizedString("tag.error.nameTooLong",
                                   value: "Tag name is too long (maximum 50 characters)",
                                   comment: "Error when tag name exceeds length limit")
        case .invalidCharacters:
            return NSLocalizedString("tag.error.invalidCharacters",
                                   value: "Tag name contains invalid characters",
                                   comment: "Error when tag name contains invalid characters")
        case .duplicateName(let existing):
            return NSLocalizedString("tag.error.duplicateName",
                                   value: "A tag named '\(existing)' already exists",
                                   comment: "Error when tag name already exists")
        case .invalidColor(let color):
            return NSLocalizedString("tag.error.invalidColor",
                                   value: "Invalid color format: \(color)",
                                   comment: "Error when color format is invalid")
        case .lowContrast:
            return NSLocalizedString("tag.error.lowContrast",
                                   value: "Color has insufficient contrast for accessibility",
                                   comment: "Error when color contrast is too low")
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
    var nfts: [NFT] = [] // Fixed: Provide default value for SwiftData
    
    // Optimized hex color validation (much faster than regex)
    private static func isValidHexColor(_ color: String) -> Bool {
        guard color.hasPrefix("#") else { return false }
        let hex = String(color.dropFirst())
        guard hex.count == 3 || hex.count == 6 else { return false }
        return hex.allSatisfy { $0.isHexDigit }
    }
    
    /// Creates a new Tag with validated name and color
    /// - Parameters:
    ///   - name: Tag name (will be trimmed, must not be empty, max 50 chars)
    ///   - color: Hex color string (e.g., "#FF5733" or "#F73")
    /// - Throws: TagError for validation failures
    init(name: String, color: String = "#007AFF") throws {
        let validatedName = try Self.validateName(name)
        let validatedColor = try Self.validateColor(color)
        
        self.name = validatedName
        self.color = validatedColor
        let now = Date()
        self.createdAt = now
        self.lastModified = now
        // nfts has default empty array
    }
    
    // MARK: - Update Methods
    
    func updateColor(_ newColor: String) -> Result<Void, TagError> {
        do {
            let validatedColor = try Self.validateColor(newColor)
            self.color = validatedColor
            self.lastModified = Date()
            return .success(())
        } catch let tagError as TagError {
            return .failure(tagError)
        } catch {
            // This should never happen with current validation, but safety first
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
            // Fallback for unexpected errors
            return .failure(.emptyName)
        }
    }
    
    // MARK: - Private Validation
    
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
        guard isValidHexColor(color) else {
            throw TagError.invalidColor(color: color)
        }
        return color
    }
    
    // MARK: - Protocol Conformance
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    
    static func == (lhs: Tag, rhs: Tag) -> Bool {
        lhs.name == rhs.name
    }
    
    // MARK: - Codable with Validation
    
    enum CodingKeys: String, CodingKey {
        case name, color, createdAt, lastModified
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.color = try container.decode(String.self, forKey: .color)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.lastModified = try container.decode(Date.self, forKey: .lastModified)
        self.nfts = [] // Initialize empty array
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(color, forKey: .color)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(lastModified, forKey: .lastModified)
    }
}
//-----------------------------------------------------------
@Model
class NFT: Codable {
    #Unique<NFT>([\.contract, \.tokenId, \.networkRawValue])
    #Index<NFT>([\.id], [\.acquiredAt], [\.collection], [\.tokenId])

    @Attribute(.unique) var id: String
    
    var contract: Contract
    var tokenId: String
    var tokenType: String?
    var name: String?
    var nftDescription: String?
    var image: Image?
    var raw: Raw?
    var collection: Collection?
    var tokenUri: String?
    var timeLastUpdated: String?
    var acquiredAt: AcquiredAt?
    var networkRawValue: String
    var contentType: String?
    var collectionName: String?
    var artistName: String?
    var animationUrl: String?
    var secureAnimationUrl: String?
    var audioUrl: String?
    var externalUrl: String?
    var modelUrl: String?
    var backgroundColor: String?
    var collectionID: String?
    var projectID: String?
    var series: String?
    var seriesID: String?
    var primaryAssetUrl: String?
    var securePrimaryAssetUrl: String?
    var previewAssetUrl: String?
    var securePreviewAssetUrl: String?
    var artistWebsite: String?
    var uniqueID: String?
    var timestamp: String?
    var tokenHash: String?
    var medium: String?
    var metadataVersion: String?
    var imageDataUrl: String?
    var secureImageDataUrl: String?
    var imageHrUrl: String?
    var secureImageHrUrl: String?
    var imageHash: String?

    // Adding the new properties from the parsing code
    var symbols: String?
    var seed: String?
    var original: String?
    var agreement: String?
    var website: String?
    var payoutAddress: String?
    var scriptType: String?
    var engineType: String?
    var accessArtworkFiles: String?

    // Numeric properties
    var sellerFeeBasisPoints: Int?
    var minted: Int?
    var isStatic: Int?
    var aspectRatio: Double?

    @Relationship(deleteRule: .cascade, inverse: \Attribute.nft)
    var attributes: [NFT.Attribute]?
    @Relationship(deleteRule: .nullify, inverse: \Tag.nfts)
    var tags: [Tag]?

    // Complex data structures
//    var imageDetails: [String: Any]?
//    var animationDetails: [String: Any]?
//    var artistRoyalty: [String: Any]?
//    var platform: [String: Any]?
//    var copyright: [String: Any]?
//    var license: [String: Any]?
//    var generatorUrl: [String: Any]?
//    var termsOfService: [String: Any]?
//    var feeRecipient: [String: Any]?
//    var royalties: [String: Any]?
//    var royaltyInfo: [String: Any]?
//    var properties: [String: Any]?
//    var exhibitionInfo: [String: Any]?
//    var features: [String: Any]?
    // MARK: Image properties
    // MARK: Artist properties
    // MARK: Project properties

    @Transient var network: Chain? {
        get {
            Chain(rawValue: networkRawValue)
        }
        set {
            // Store the raw value when the enum is set
            networkRawValue = newValue?.rawValue ?? ""
        }
    }
    
    func isMusic() -> Bool {
        let hasAudioContentType = contentType?.starts(with: "audio/") == true
        let hasAudioUrl = audioUrl?.isEmpty == false
        
        let animationUrl = self.animationUrl ?? ""
        
        let hasAudioAnimation = animationUrl.contains(".mp3") ||
        animationUrl.contains(".m4a") ||
        animationUrl.contains(".wav") ||
        animationUrl.contains(".flac")
        
        return hasAudioContentType || hasAudioUrl || hasAudioAnimation
    }
    
    var musicURL: URL? {
        guard isMusic() else { return nil }
        
        let animationUrl = self.animationUrl ?? ""
        
        if animationUrl.contains(".mp3") ||
            animationUrl.contains(".m4a") ||
            animationUrl.contains(".wav") ||
            animationUrl.contains(".flac") {
            return URL(string: animationUrl)
        } else if let audioUrl, !audioUrl.isEmpty {
            return URL(string: audioUrl)
        } else {
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case contract
        case tokenId
        case tokenType
        case name
        case nftDescription = "description"
        case image
        case raw
        case collection
        case tokenUri
        case timeLastUpdated
        case acquiredAt
    }
    
    init(id: String, contract: Contract, tokenId: String, tokenType: String? = nil, name: String? = nil, nftDescription: String? = nil, image: Image? = nil, raw: Raw? = nil, collection: Collection?, tokenUri: String? = nil, timeLastUpdated: String? = nil, acquiredAt: AcquiredAt? = nil, network: Chain = .ethMainnet, contentType: String? = nil, collectionName: String? = nil, artistName: String? = nil, animationUrl: String? = nil, secureAnimationUrl: String? = nil, audioUrl: String? = nil, tags: [Tag]? = nil) {
        self.id = id
        self.contract = contract
        self.tokenId = tokenId
        self.tokenType = tokenType
        self.name = name
        self.nftDescription = nftDescription
        self.image = image
        self.raw = raw
        self.collection = collection
        self.tokenUri = tokenUri
        self.timeLastUpdated = timeLastUpdated
        self.acquiredAt = acquiredAt
        self.networkRawValue = network.rawValue
        self.contentType = contentType
        self.collectionName = collectionName
        self.artistName = artistName
        self.animationUrl = animationUrl
        self.secureAnimationUrl = secureAnimationUrl
        self.audioUrl = audioUrl
        self.tags = tags ?? []
    }

    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType)
        self.tokenType = tokenType
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        self.name = name
        nftDescription = try container.decodeIfPresent(String.self, forKey: .nftDescription)
        image = try container.decodeIfPresent(Image.self, forKey: .image)
        raw = try container.decodeIfPresent(Raw.self, forKey: .raw)
        collection = try container.decodeIfPresent(Collection.self, forKey: .collection)
        let tokenUri = try container.decodeIfPresent(String.self, forKey: .tokenUri)
        self.tokenUri = tokenUri
        timeLastUpdated = try container.decodeIfPresent(String.self, forKey: .timeLastUpdated)
        acquiredAt = try container.decodeIfPresent(AcquiredAt.self, forKey: .acquiredAt)
        networkRawValue = Chain.ethMainnet.rawValue

        let tokenId = try container.decode(String.self, forKey: .tokenId)
        self.tokenId = tokenId
        let contract = try container.decode(Contract.self, forKey: .contract)
        self.contract = contract
        let contractAddress = contract.address ?? ("unknown" + (tokenType ?? "") + (name ?? "") + (tokenUri ?? ""))
        let networkPrefix = Chain.ethMainnet.rawValue
        id = "\(networkPrefix):\(contractAddress):\(tokenId)"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(contract, forKey: .contract)
        try container.encode(tokenId, forKey: .tokenId)
        try container.encodeIfPresent(tokenType, forKey: .tokenType)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(nftDescription, forKey: .nftDescription)
        try container.encodeIfPresent(image, forKey: .image)
        try container.encodeIfPresent(raw, forKey: .raw)
        try container.encodeIfPresent(collection, forKey: .collection)
        try container.encodeIfPresent(tokenUri, forKey: .tokenUri)
        try container.encodeIfPresent(timeLastUpdated, forKey: .timeLastUpdated)
        try container.encodeIfPresent(acquiredAt, forKey: .acquiredAt)
    }
    
    
    @Model
    class Contract: Codable {
        @Attribute(.unique) var address: String?

        init(address: String?) {
            self.address = address
        }
        
        enum CodingKeys: String, CodingKey {
            case address
        }
        
        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            address = try container.decode(String.self, forKey: .address)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(address, forKey: .address)
        }
    }
    
    @Model
    class Image: Codable {
        var originalUrl: String?
        var thumbnailUrl: String?
        var secureUrl: String?

        init(originalUrl: String? = nil, thumbnailUrl: String? = nil) {
            self.originalUrl = originalUrl
            self.thumbnailUrl = thumbnailUrl
        }
        
        enum CodingKeys: String, CodingKey {
            case originalUrl
            case thumbnailUrl
        }
        
        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            originalUrl = try container.decodeIfPresent(String.self, forKey: .originalUrl)
            thumbnailUrl = try container.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(originalUrl, forKey: .originalUrl)
            try container.encodeIfPresent(thumbnailUrl, forKey: .thumbnailUrl)
        }
    }
    
    @Model
    class Raw: Codable {
        var tokenUri: String?
        var metadata: [String: JSONValue]?
        var error: String?

        init(tokenUri: String? = nil, metadata: [String: JSONValue]? = nil) {
            self.tokenUri = tokenUri
            self.metadata = metadata
        }
        
        enum CodingKeys: String, CodingKey {
            case tokenUri
            case metadata
        }
        
        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tokenUri = try container.decodeIfPresent(String.self, forKey: .tokenUri)
            do {
                metadata = try container.decodeIfPresent([String: JSONValue].self, forKey: .metadata)
            } catch {
                let website = try container.decodeIfPresent(String.self, forKey: .metadata)
                metadata = ["data": .string(website ?? "")]
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(tokenUri, forKey: .tokenUri)
            try container.encodeIfPresent(metadata, forKey: .metadata)
        }
    }
    
    @Model
    class NFTMetadata: Codable {
        var image: String?
        var name: String?
        var metadataDescription: String?
        var attributes: [Attribute]?
        
        enum CodingKeys: String, CodingKey {
            case image
            case name
            case metadataDescription = "description"
            case attributes
        }
        
        init(image: String? = nil, name: String? = nil, metadataDescription: String? = nil, attributes: [Attribute]? = nil) {
            self.image = image
            self.name = name
            self.metadataDescription = metadataDescription
            self.attributes = attributes
        }
        
        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            image = try container.decodeIfPresent(String.self, forKey: .image)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            metadataDescription = try container.decodeIfPresent(String.self, forKey: .metadataDescription)
            attributes = try container.decodeIfPresent([Attribute].self, forKey: .attributes)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(image, forKey: .image)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encodeIfPresent(metadataDescription, forKey: .metadataDescription)
            try container.encodeIfPresent(attributes, forKey: .attributes)
        }
    }
    
    @Model
    class Attribute: Codable, Identifiable {
        var value: String
        var traitType: String?

        var nft: NFT?

        enum CodingKeys: String, CodingKey {
            case value
            case traitType = "trait_type"
        }
        
        init(value: String, traitType: String? = nil) {
            self.value = value
            self.traitType = traitType
        }
        
        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            value = try container.decode(String.self, forKey: .value)
            traitType = try container.decodeIfPresent(String.self, forKey: .traitType)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(value, forKey: .value)
            try container.encodeIfPresent(traitType, forKey: .traitType)
        }
    }
    
    @Model
    class Collection: Codable {
        @Attribute(.unique) var name: String?
        
        enum CodingKeys: String, CodingKey {
            case name
        }
        
        init(name: String?) {
            self.name = name
        }
        
        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(name, forKey: .name)
        }
    }
    
    @Model
    class AcquiredAt: Codable {
        var blockTimestamp: String?
        
        enum CodingKeys: String, CodingKey {
            case blockTimestamp
        }
        
        init(blockTimestamp: String? = nil) {
            self.blockTimestamp = blockTimestamp
        }
        
        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            blockTimestamp = try container.decodeIfPresent(String.self, forKey: .blockTimestamp)
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(blockTimestamp, forKey: .blockTimestamp)
        }
    }
}

extension Dictionary where Key == String, Value == JSONValue {

    var image: String? {
        self["image"]?.stringValue
    }

    var name: String? {
        self["name"]?.stringValue
    }

    var metadataDescription: String? {
        self["description"]?.stringValue
    }

    var attributes: [NFT.Attribute]? {
        guard case let .array(jsonArray)? = self["attributes"] else { return nil }

        return jsonArray.compactMap { value in
            guard case let .object(attrDict) = value else { return nil }
            return decodeAttribute(from: attrDict)
        }
    }

    private func decodeAttribute(from dict: [String: JSONValue]) -> NFT.Attribute? {
        do {
            let data = try JSONEncoder().encode(dict)
            return try JSONDecoder().decode(NFT.Attribute.self, from: data)
        } catch {
            print("Failed to decode Attribute: \(error)")
            return nil
        }
    }

    /// Optional helper to get the entire `NFTMetadata`-like object
    var asNFTMetadata: NFT.NFTMetadata {
        NFT.NFTMetadata(
            image: self.image,
            name: self.name,
            metadataDescription: self.metadataDescription,
            attributes: self.attributes
        )
    }
}




//
//  NFTExamples.swift
//  Real NFT Examples Dataset
//
//  Generated examples based on actual NFT collections and types

import Foundation

class NFTExamples {
    static let musicNFT1 = NFT(
        id: "0x1234567890abcdef1234567890abcdef12345678:1",
        contract: NFT.Contract(address: "0x1234567890abcdef1234567890abcdef12345678"),
        tokenId: "1",
        tokenType: "ERC721",
        name: "Grimes - War Nymph",
        nftDescription: "A unique music NFT from Grimes' collection, featuring the song 'War Nymph' with exclusive digital artwork.",
        image: NFT.Image(
            originalUrl: "https://example.com/grimes/war_nymph.jpg",
            thumbnailUrl: "https://example.com/grimes/war_nymph_thumbnail.jpg"
        ),
        raw: nil,
        collection: NFT.Collection(name: "Grimes NFTs"),
        tokenUri: "https://example.com/grimes/war_nymph.json",
        timeLastUpdated: "2025-07-22T16:00:00Z",
        acquiredAt: NFT.AcquiredAt(blockTimestamp: "2025-07-20T10:30:00Z"),
        network: .ethMainnet,
        contentType: "audio/mp3",
        collectionName: "Grimes NFTs",
        artistName: "Grimes",
        audioUrl: "https://example.com/grimes/war_nymph.mp3"
    )
    // MARK: - Music NFT Example
    static let musicNFT = NFT(
        id: "0x495f947276749ce646f68ac8c248420045cb7b5e:1",
        contract: NFT.Contract(address: "0x495f947276749ce646f68ac8c248420045cb7b5e"),
        tokenId: "1",
        tokenType: "ERC721",
        name: "Eternal Frequencies #001",
        nftDescription: "An experimental ambient composition exploring the intersection of generative music and blockchain technology. This piece evolves over 4 minutes and 32 seconds, featuring layered synthesizers and field recordings.",
        image: NFT.Image(
            originalUrl: "https://ipfs.io/ipfs/QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o",
            thumbnailUrl: "https://ipfs.io/ipfs/QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o/thumb.jpg"
        ),
        raw: NFT.Raw(
            tokenUri: "https://api.opensea.io/api/v1/metadata/0x495f947276749ce646f68ac8c248420045cb7b5e/1",
            metadata: [
                "name": .string("Eternal Frequencies #001"),
                "description": .string("An experimental ambient composition exploring the intersection of generative music and blockchain technology."),
                "image": .string("https://ipfs.io/ipfs/QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o"),
                "animation_url": .string("https://ipfs.io/ipfs/QmPK1s3pNYLi9ERiq3BDxKa4XosgWwFRQUydHUtz4YgpqB/eternal_frequencies_001.mp3"),
                "attributes": .array([
                    .object([
                        "trait_type": .string("Genre"),
                        "value": .string("Ambient Electronic")
                    ]),
                    .object([
                        "trait_type": .string("Duration"),
                        "value": .string("4:32")
                    ]),
                    .object([
                        "trait_type": .string("BPM"),
                        "value": .string("72")
                    ]),
                    .object([
                        "trait_type": .string("Key"),
                        "value": .string("A Minor")
                    ]),
                    .object([
                        "trait_type": .string("Instruments"),
                        "value": .string("Modular Synthesizer, Field Recordings")
                    ])
                ])
            ]
        ),
        collection: NFT.Collection(name: "SoundWaves Collective"),
        tokenUri: "https://api.opensea.io/api/v1/metadata/0x495f947276749ce646f68ac8c248420045cb7b5e/1",
        timeLastUpdated: "2024-01-15T10:30:00.000Z",
        acquiredAt: NFT.AcquiredAt(blockTimestamp: "2024-01-15T10:30:00.000Z"),
        network: .ethMainnet,
        contentType: "audio/mpeg",
        collectionName: "SoundWaves Collective",
        artistName: "Luna Cipher",
        animationUrl: "https://ipfs.io/ipfs/QmPK1s3pNYLi9ERiq3BDxKa4XosgWwFRQUydHUtz4YgpqB/eternal_frequencies_001.mp3", audioUrl: "https://ipfs.io/ipfs/QmPK1s3pNYLi9ERiq3BDxKa4XosgWwFRQUydHUtz4YgpqB/eternal_frequencies_001.mp3"
    ).applying {
        $0.externalUrl = "https://lunaciphermusic.com"
        $0.artistWebsite = "https://lunaciphermusic.com"
        $0.medium = "Digital Audio"
        $0.sellerFeeBasisPoints = 750 // 7.5% royalty
        $0.aspectRatio = 1.0
    }

    // MARK: - Popular PFP NFT (Bored Ape Style)
    static let pfpNFT = NFT(
        id: "0xbc4ca0eda7647a8ab7c2061c2e118a18a936f13d:5234",
        contract: NFT.Contract(address: "0xbc4ca0eda7647a8ab7c2061c2e118a18a936f13d"),
        tokenId: "5234",
        tokenType: "ERC721",
        name: "Bored Ape Yacht Club #5234",
        nftDescription: "A unique Bored Ape with rare traits. This ape is bored and ready for the metaverse!",
        image: NFT.Image(
            originalUrl: "https://ipfs.io/ipfs/QmRRPWG96cmgTn2qSzjwr2qvfNEuhunv6FNeMFGa9bx6mQ",
            thumbnailUrl: "https://ipfs.io/ipfs/QmRRPWG96cmgTn2qSzjwr2qvfNEuhunv6FNeMFGa9bx6mQ"
        ),
        raw: NFT.Raw(
            tokenUri: "https://ipfs.io/ipfs/QmeSjSinHpPnmXmspMjwiXyN6zS4E9zccariGR3jxcaWtq/5234",
            metadata: [
                "name": .string("Bored Ape Yacht Club #5234"),
                "description": .string("A unique Bored Ape with rare traits. This ape is bored and ready for the metaverse!"),
                "image": .string("https://ipfs.io/ipfs/QmRRPWG96cmgTn2qSzjwr2qvfNEuhunv6FNeMFGa9bx6mQ"),
                "attributes": .array([
                    .object([
                        "trait_type": .string("Background"),
                        "value": .string("Purple")
                    ]),
                    .object([
                        "trait_type": .string("Fur"),
                        "value": .string("Golden Brown")
                    ]),
                    .object([
                        "trait_type": .string("Eyes"),
                        "value": .string("Laser Eyes")
                    ]),
                    .object([
                        "trait_type": .string("Mouth"),
                        "value": .string("Bored Unshaven")
                    ]),
                    .object([
                        "trait_type": .string("Hat"),
                        "value": .string("Safari")
                    ]),
                    .object([
                        "trait_type": .string("Clothes"),
                        "value": .string("Leather Jacket")
                    ])
                ])
            ]
        ),
        collection: NFT.Collection(name: "Bored Ape Yacht Club"),
        tokenUri: "https://ipfs.io/ipfs/QmeSjSinHpPnmXmspMjwiXyN6zS4E9zccariGR3jxcaWtq/5234",
        timeLastUpdated: "2024-01-20T14:22:00.000Z",
        acquiredAt: NFT.AcquiredAt(blockTimestamp: "2021-04-30T12:15:00.000Z"),
        network: .ethMainnet,
        contentType: "image/png",
        collectionName: "Bored Ape Yacht Club",
        artistName: "Yuga Labs"
    ).applying {
        $0.externalUrl = "https://boredapeyachtclub.com"
        $0.backgroundColor = "purple"
        $0.sellerFeeBasisPoints = 250 // 2.5% royalty
        $0.aspectRatio = 1.0
    }

    // MARK: - Art Blocks Generative Art
    static let generativeArt = NFT(
        id: "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270:23000456",
        contract: NFT.Contract(address: "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270"),
        tokenId: "23000456",
        tokenType: "ERC721",
        name: "Chromie Squiggle #456",
        nftDescription: "A simple, elegant, and unpredictable algorithm. Chromie Squiggles are the first 'Art Blocks Curated' project and the project that started the Art Blocks platform.",
        image: NFT.Image(
            originalUrl: "https://api.artblocks.io/image/23000456",
            thumbnailUrl: "https://api.artblocks.io/image/23000456"
        ),
        raw: NFT.Raw(
            tokenUri: "https://api.artblocks.io/token/23000456",
            metadata: [
                "name": .string("Chromie Squiggle #456"),
                "description": .string("A simple, elegant, and unpredictable algorithm."),
                "image": .string("https://api.artblocks.io/image/23000456"),
                "generator_url": .string("https://generator.artblocks.io/23000456"),
                "attributes": .array([
                    .object([
                        "trait_type": .string("Color Spread"),
                        "value": .string("High")
                    ]),
                    .object([
                        "trait_type": .string("Direction"),
                        "value": .string("Right and Up")
                    ]),
                    .object([
                        "trait_type": .string("Height"),
                        "value": .string("Normal")
                    ]),
                    .object([
                        "trait_type": .string("Pipe Count"),
                        "value": .string("5")
                    ]),
                    .object([
                        "trait_type": .string("Spectrum"),
                        "value": .string("Hyper")
                    ])
                ])
            ]
        ),
        collection: NFT.Collection(name: "Art Blocks Curated"),
        tokenUri: "https://api.artblocks.io/token/23000456",
        timeLastUpdated: "2024-01-18T09:45:00.000Z",
        acquiredAt: NFT.AcquiredAt(blockTimestamp: "2020-11-27T16:20:00.000Z"),
        network: .ethMainnet,
        contentType: "image/svg+xml",
        collectionName: "Chromie Squiggle",
        artistName: "Snowfro"
    ).applying {
        $0.externalUrl = "https://artblocks.io"
        $0.artistWebsite = "https://artblocks.io"
        $0.projectID = "0"
        $0.scriptType = "p5.js"
        $0.engineType = "Art Blocks Engine"
        $0.sellerFeeBasisPoints = 250 // 2.5% royalty
        $0.aspectRatio = 1.0
        $0.isStatic = 0 // Dynamic/generative
    }

    // MARK: - Photography NFT
    static let photographyNFT = NFT(
        id: "0x60f80121c31a0d46b5279700f9df786054aa5ee5:123456",
        contract: NFT.Contract(address: "0x60f80121c31a0d46b5279700f9df786054aa5ee5"),
        tokenId: "123456",
        tokenType: "ERC721",
        name: "Urban Solitude #17",
        nftDescription: "A contemplative street photography piece capturing the isolation and beauty found in urban environments during golden hour. Shot in downtown Tokyo, 2023.",
        image: NFT.Image(
            originalUrl: "https://ipfs.io/ipfs/QmNLei78zWmzUdbeRB3CiUfAizWUrbeeZh5K1rhAQKCh51",
            thumbnailUrl: "https://ipfs.io/ipfs/QmNLei78zWmzUdbeRB3CiUfAizWUrbeeZh5K1rhAQKCh51/thumb.jpg"
        ),
        raw: NFT.Raw(
            tokenUri: "https://raible.mypinata.cloud/ipfs/QmPtP2BNkUvGEuEPz7gBAw6qm96VxeqAjqQS6jgKG89V9M/123456.json",
            metadata: [
                "name": .string("Urban Solitude #17"),
                "description": .string("A contemplative street photography piece capturing the isolation and beauty found in urban environments."),
                "image": .string("https://ipfs.io/ipfs/QmNLei78zWmzUdbeRB3CiUfAizWUrbeeZh5K1rhAQKCh51"),
                "attributes": .array([
                    .object([
                        "trait_type": .string("Location"),
                        "value": .string("Tokyo, Japan")
                    ]),
                    .object([
                        "trait_type": .string("Camera"),
                        "value": .string("Leica Q2")
                    ]),
                    .object([
                        "trait_type": .string("Lens"),
                        "value": .string("28mm f/1.7")
                    ]),
                    .object([
                        "trait_type": .string("ISO"),
                        "value": .string("400")
                    ]),
                    .object([
                        "trait_type": .string("Aperture"),
                        "value": .string("f/2.8")
                    ]),
                    .object([
                        "trait_type": .string("Year"),
                        "value": .string("2023")
                    ])
                ])
            ]
        ),
        collection: NFT.Collection(name: "Foundation"),
        tokenUri: "https://raible.mypinata.cloud/ipfs/QmPtP2BNkUvGEuEPz7gBAw6qm96VxeqAjqQS6jgKG89V9M/123456.json",
        timeLastUpdated: "2024-01-12T11:15:00.000Z",
        acquiredAt: NFT.AcquiredAt(blockTimestamp: "2023-08-15T14:30:00.000Z"),
        network: .ethMainnet,
        contentType: "image/jpeg",
        collectionName: "Urban Chronicles",
        artistName: "Kenji Nakamura"
    ).applying {
        $0.externalUrl = "https://foundation.app"
        $0.artistWebsite = "https://kenjinakamura.photo"
        $0.medium = "Digital Photography"
        $0.sellerFeeBasisPoints = 1000 // 10% royalty
        $0.aspectRatio = 1.5
    }

    // MARK: - Gaming/Metaverse NFT
    static let gamingNFT = NFT(
        id: "0x7bd29408f11d2bfc23c34f18275bbf23bb716bc7:15678",
        contract: NFT.Contract(address: "0x7bd29408f11d2bfc23c34f18275bbf23bb716bc7"),
        tokenId: "15678",
        tokenType: "ERC721",
        name: "CryptoVoxels Parcel #15678",
        nftDescription: "A prime real estate parcel in the heart of Origin City. This 16x16 plot includes building permissions and comes with exclusive neighborhood benefits.",
        image: NFT.Image(
            originalUrl: "https://www.cryptovoxels.com/parcels/15678.png",
            thumbnailUrl: "https://www.cryptovoxels.com/parcels/15678_thumb.png"
        ),
        raw: NFT.Raw(
            tokenUri: "https://www.cryptovoxels.com/p/15678",
            metadata: [
                "name": .string("CryptoVoxels Parcel #15678"),
                "description": .string("A prime real estate parcel in the heart of Origin City."),
                "image": .string("https://www.cryptovoxels.com/parcels/15678.png"),
                "external_url": .string("https://www.cryptovoxels.com/play?coords=N@15678"),
                "attributes": .array([
                    .object([
                        "trait_type": .string("Area"),
                        "value": .string("256")
                    ]),
                    .object([
                        "trait_type": .string("Height"),
                        "value": .string("20")
                    ]),
                    .object([
                        "trait_type": .string("Suburb"),
                        "value": .string("Origin City")
                    ]),
                    .object([
                        "trait_type": .string("Island"),
                        "value": .string("Origin")
                    ]),
                    .object([
                        "trait_type": .string("Type"),
                        "value": .string("parcel")
                    ]),
                    .object([
                        "trait_type": .string("Elevation"),
                        "value": .string("20")
                    ])
                ])
            ]
        ),
        collection: NFT.Collection(name: "CryptoVoxels"),
        tokenUri: "https://www.cryptovoxels.com/p/15678",
        timeLastUpdated: "2024-01-10T16:45:00.000Z",
        acquiredAt: NFT.AcquiredAt(blockTimestamp: "2022-03-12T10:20:00.000Z"),
        network: .ethMainnet,
        contentType: "application/json",
        collectionName: "CryptoVoxels",
        artistName: "Cryptovoxels Team"
    ).applying {
        $0.externalUrl = "https://www.cryptovoxels.com/play?coords=N@15678"
        $0.modelUrl = "https://www.cryptovoxels.com/parcels/15678.glb"
        $0.sellerFeeBasisPoints = 500 // 5% royalty
        $0.aspectRatio = 1.0
    }

    // MARK: - Domain Name NFT
    static let domainNFT = NFT(
        id: "0x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85:68789456",
        contract: NFT.Contract(address: "0x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85"),
        tokenId: "68789456789123456789012345678901234567890123456789012345678901",
        tokenType: "ERC721",
        name: "crypto.eth",
        nftDescription: "Ethereum Name Service domain name for crypto.eth - a premium Web3 domain name.",
        image: NFT.Image(
            originalUrl: "https://metadata.ens.domains/mainnet/0x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85/68789456789123456789012345678901234567890123456789012345678901/image",
            thumbnailUrl: "https://metadata.ens.domains/mainnet/0x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85/68789456789123456789012345678901234567890123456789012345678901/image"
        ),
        raw: NFT.Raw(
            tokenUri: "https://metadata.ens.domains/mainnet/0x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85/68789456789123456789012345678901234567890123456789012345678901",
            metadata: [
                "name": .string("crypto.eth"),
                "description": .string("crypto.eth, an ENS name."),
                "image": .string("https://metadata.ens.domains/mainnet/0x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85/68789456789123456789012345678901234567890123456789012345678901/image"),
                "attributes": .array([
                    .object([
                        "trait_type": .string("Length"),
                        "value": .string("6")
                    ]),
                    .object([
                        "trait_type": .string("Segment Length"),
                        "value": .string("6")
                    ]),
                    .object([
                        "trait_type": .string("Character Set"),
                        "value": .string("letter")
                    ]),
                    .object([
                        "trait_type": .string("Registration Date"),
                        "value": .string("2022-05-01")
                    ]),
                    .object([
                        "trait_type": .string("Expiration Date"),
                        "value": .string("2025-05-01")
                    ])
                ])
            ]
        ),
        collection: NFT.Collection(name: "ENS: Ethereum Name Service"),
        tokenUri: "https://metadata.ens.domains/mainnet/0x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85/68789456789123456789012345678901234567890123456789012345678901",
        timeLastUpdated: "2024-01-15T08:20:00.000Z",
        acquiredAt: NFT.AcquiredAt(blockTimestamp: "2022-05-01T12:00:00.000Z"),
        network: .ethMainnet,
        contentType: "image/svg+xml",
        collectionName: "ENS: Ethereum Name Service",
        artistName: "ENS Team"
    ).applying {
        $0.externalUrl = "https://app.ens.domains/name/crypto.eth"
        $0.sellerFeeBasisPoints = 0 // No royalties on ENS
        $0.aspectRatio = 1.0
    }

    static let artNFT = NFT(
        id: "0xabcdef1234567890abcdef1234567890abcdef12:2",
        contract: NFT.Contract(address: "0xabcdef1234567890abcdef1234567890abcdef12"),
        tokenId: "2",
        tokenType: "ERC721",
        name: "DigitalDreamer - Nebula Voyage",
        nftDescription: "A stunning digital artwork by DigitalDreamer, depicting a journey through a vibrant nebula.",
        image: NFT.Image(
            originalUrl: "https://example.com/digitaldreamer/nebula_voyage.png",
            thumbnailUrl: "https://example.com/digitaldreamer/nebula_voyage_thumbnail.png"
        ),
        raw: nil,
        collection: NFT.Collection(name: "DigitalDreamer Collection"),
        tokenUri: "https://example.com/digitaldreamer/nebula_voyage.json",
        timeLastUpdated: "2025-07-22T15:00:00Z",
        acquiredAt: NFT.AcquiredAt(blockTimestamp: "2025-07-19T09:00:00Z"),
        network: .ethMainnet,
        contentType: "image/png",
        collectionName: "DigitalDreamer Collection",
        artistName: "DigitalDreamer"
    )

    static let collectibleNFT = NFT(
        id: "0xfedcba9876543210fedcba9876543210fedcba98:3",
        contract: NFT.Contract(address: "0xfedcba9876543210fedcba9876543210fedcba98"),
        tokenId: "3",
        tokenType: "ERC721",
        name: "CyberPets #3",
        nftDescription: "A unique digital pet from the CyberPets collection, with traits: color - blue, eyes - laser.",
        image: NFT.Image(
            originalUrl: "https://example.com/cyberpets/pet3.png",
            thumbnailUrl: "https://example.com/cyberpets/pet3_thumbnail.png"
        ),
        raw: nil,
        collection: NFT.Collection(name: "CyberPets"),
        tokenUri: "https://example.com/cyberpets/pet3.json",
        timeLastUpdated: "2025-07-22T14:00:00Z",
        acquiredAt: NFT.AcquiredAt(blockTimestamp: "2025-07-18T12:00:00Z"),
        network: .ethMainnet,
        contentType: "image/png",
        collectionName: "CyberPets",
        artistName: "CryptoCreators"
    )

    //Music NFT – "Ethereal Tides" by DJ Aurora
    static let musicNFT2 = NFT(
        id: "0xABCDEF1234567890:001",
        contract: .init(address: "0xABCDEF1234567890"),
        tokenId: "001",
        tokenType: "ERC721",
        name: "Ethereal Tides",
        nftDescription: "A meditative ambient track blending analog synths with Ethereum transaction hash data.",
        image: .init(originalUrl: "https://example.com/images/ethereal-tides.png"),
        collection: .init(name: "Ambient on Chain"), tokenUri: "ipfs://QmMusic1234", network: .ethMainnet, contentType: "audio/mpeg", collectionName: "Ambient on Chain", artistName: "DJ Aurora", animationUrl: "https://example.com/visualizer/ethereal-tides", audioUrl: "https://example.com/audio/ethereal-tides.mp3"
    )

    //Visual Art NFT – "Cyber Garden"
    static let artNFT2 = NFT(
        id: "0xART123456789:2048",
        contract: .init(address: "0xART123456789"),
        tokenId: "2048",
        tokenType: "ERC721",
        name: "Cyber Garden",
        nftDescription: "A surrealist depiction of a digital utopia, built from GAN-generated flora.",
        image: .init(originalUrl: "https://example.com/cyber-garden.jpg"),
        collection: .init(name: "Neon Eden"), tokenUri: "ipfs://QmVisual2048", network: .ethMainnet, contentType: "image/jpeg",
        collectionName: "Neon Eden", artistName: "Lumen Vox",
    )

    //Generative PFP NFT – "Moonpunk #4890"
    static let collectibleNFT2 = NFT(
        id: "0xPFP56789:4890",
        contract: .init(address: "0xPFP56789"),
        tokenId: "4890",
        tokenType: "ERC721",
        name: "Moonpunk #4890",
        nftDescription: "Moonpunk sporting a cyber jacket and laser eyes. Common traits.",
        image: .init(originalUrl: "https://moonpunks.io/images/4890.png"),
        collection: .init(name: "Moonpunks"), tokenUri: "ipfs://QmMoonPunk4890", network: .ethMainnet, contentType: "image/png",
        collectionName: "Moonpunks",
        artistName: "Moon Labs",
    )

    // 3D Model NFT – "Voxel Sphinx"
    static let nft3DModel = NFT(
        id: "0x3DModelVault:77",
        contract: .init(address: "0x3DModelVault"),
        tokenId: "77",
        tokenType: "ERC721",
        name: "Voxel Sphinx",
        nftDescription: "An ancient guardian rebuilt as a voxel model, optimized for use in metaverse environments.",
        image: .init(originalUrl: "https://models.example.com/voxel-sphinx-thumb.png"),
        collection: .init(name: "Metaverse Relics"), tokenUri: "ipfs://QmVoxelSphinx77", network: .ethMainnet, contentType: "model/gltf-binary",
        collectionName: "Metaverse Relics", artistName: "VoxelMaster",
    )

    //Text/Poetry NFT – "Solidity Sonnet #1"
    static let textPoetryNFT = NFT(
        id: "0xPoetryVault123:001",
        contract: .init(address: "0xPoetryVault123"),
        tokenId: "001",
        tokenType: "ERC721",
        name: "Solidity Sonnet #1",
        nftDescription: "A poetic ode to smart contracts written entirely in rhyming couplets.",
        image: .init(originalUrl: "https://nftpoems.io/cover1.png"),
        collection: .init(name: "Gaslight Verses"), tokenUri: "ipfs://QmPoemText001", network: .ethMainnet, contentType: "text/plain",
        collectionName: "Gaslight Verses",
        artistName: "Versebyte"
    )

    // MARK: - All Examples Array
    static let allExamples = [
        musicNFT,
        pfpNFT,
        generativeArt,
        photographyNFT,
        gamingNFT,
        domainNFT,
        artNFT,
        collectibleNFT,
        musicNFT2,
        collectibleNFT2,
        nft3DModel,
        textPoetryNFT
    ]
}

// MARK: - Helper Extension for Applying Properties
extension NFT {
    func applying(_ closure: (NFT) -> Void) -> NFT {
        closure(self)
        return self
    }
}
