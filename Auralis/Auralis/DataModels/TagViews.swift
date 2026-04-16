import SwiftUI
import SwiftData

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
                        SystemImage("plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                TagCreateUpdateView()
            }
            .sheet(item: $tagToUpdate) { tag in
                TagCreateUpdateView(existingTag: tag)
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { lastError != nil },
                    set: { isPresented in
                        if !isPresented {
                            lastError = nil
                        }
                    }
                )
            ) {
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

struct TagCreateUpdateView: View {
    @Query(sort: [SortDescriptor(\Tag.name)]) private var tags: [Tag]
    @Environment(\.modelContext) private var modelContext

    @State private var existingTag: Tag?
    @State private var tagName: String
    @State private var tagColor: String
    @State private var validationError: TagError?

    @Environment(\.dismiss) private var dismiss

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
        let trimmedName = tagName.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            throw TagError.emptyName
        }

        if trimmedName.count > Constants.maxNameLength {
            throw TagError.nameTooLong
        }

        if trimmedName.rangeOfCharacter(from: Constants.allowedCharacterSet.inverted) != nil {
            throw TagError.invalidCharacters
        }

        let lowercasedName = trimmedName.lowercased()
        if Set(tags.map { $0.name.lowercased() }).contains(lowercasedName) &&
            existingTag?.name.lowercased() != lowercasedName {
            throw TagError.duplicateName(existing: lowercasedName)
        }

        let trimmedColor = tagColor.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedColor.isEmpty {
            throw TagError.invalidColor(color: trimmedColor)
        }

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
            validationError = TagError.operationFailed(underlying: error)
        }

        validationError = nil

        let trimmedName = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanColor = tagColor
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .withLeadingHashPrefix()

        let didSave: Bool
        if existingTag != nil {
            didSave = updateTag(name: trimmedName, color: cleanColor)
        } else {
            didSave = createTag(name: trimmedName, color: cleanColor)
        }

        if didSave {
            dismiss()
        }
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

    private func validateColor(_ color: String) throws -> String {
        let validated = try Tag.validateColor(color)

        if let uiColor = UIColor(hex: validated) {
            let contrastRatio = uiColor.contrastRatio(with: .white)
            if contrastRatio < 4.5 {
                throw TagError.lowContrast
            }
        }

        return validated
    }

    private func createTag(name: String, color: String) -> Bool {
        validationError = nil

        do {
            let validatedName = try self.processAndValidateTagName(name)
            let validatedColor = try self.validateColor(color)

            let tag = try Tag(name: validatedName, color: validatedColor)

            self.modelContext.insert(tag)
            try self.modelContext.save()
            return true
        } catch let error as TagError {
            validationError = error
        } catch {
            validationError = TagError.operationFailed(underlying: error)
        }

        return false
    }

    private func updateTag(name: String, color: String) -> Bool {
        validationError = nil

        guard let tag = existingTag else {
            return false
        }
        do {
            let nameResult = tag.updateName(name)
            let colorResult = tag.updateColor(color)

            try nameResult.get()
            try colorResult.get()

            try self.modelContext.save()
            return true
        } catch let error as TagError {
            validationError = error
        } catch {
            validationError = TagError.operationFailed(underlying: error)
        }

        return false
    }
}

struct ColorPickerWithHex: View {
    @State private var selectedColor = Color.blue

    var body: some View {
        VStack(spacing: 20) {
            Text("Color Picker")
                .font(.largeTitle)
                .fontWeight(.bold)

            RoundedRectangle(cornerRadius: 12)
                .fill(selectedColor)
                .frame(width: 200, height: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray, lineWidth: 1)
                )

            ColorPicker("Select Color", selection: $selectedColor)
                .frame(maxWidth: 300)

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
                    .textSelection(.enabled)
            }
        }
        .padding()
    }
}
