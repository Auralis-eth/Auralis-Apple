import SwiftUI
import PhotosUI
import SwiftData
import ImagePlayground


//func generateImageFromPlayground() async throws {
//    let seletedStyle: ImagePlaygroundStyle = .animation
//    let creator = try await ImageCreator()
//    let images = creator.images(for: [.text("Aurora Borealis over the Arctic and Rocky Mounts")], style: seletedStyle, limit: 4)
//
//    for try await image in images {
//        print("Generated image:")
//        print(image.cgImage)
//    }
//}
//


struct NewPlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    
    @State private var title: String = ""
    @State private var descriptionText: String = ""
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var playlistImage: Image? = nil
    @State private var selectedImageData: Data? = nil
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var isShowingPlayground = false
    
    let onSuccess: (String) -> Void
    
    @FocusState private var titleFieldFocused: Bool
    
    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private var isTitleValid: Bool {
        !trimmedTitle.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Group {
                        if let data = selectedImageData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 150, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .accessibilityLabel(NSLocalizedString("Selected Cover Image", comment: "Accessibility label for selected cover image"))
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.secondary.opacity(0.1))
                                .frame(width: 150, height: 150)
                                .overlay(
                                    Image(systemName: "photo")
                                        .font(.system(size: 50))
                                        .foregroundColor(.secondary)
                                )
                                .accessibilityLabel(NSLocalizedString("No Cover Image Selected", comment: "Accessibility label for no cover image"))
                        }
                    }
                    HStack {
                        
                        Spacer()
                        if supportsImagePlayground {
                            Button {
                                isShowingPlayground = true
                            } label: {
                                SystemImage("sparkles")
                                    .padding()
                                    .background(Color.surface)
                            }

                        } else {
                            PhotosPicker(
                                selection: $photoItem,
                                matching: .images,
                                photoLibrary: .shared()) {
                                    Text(NSLocalizedString("Choose Cover", comment: "Button label to choose cover image"))
                                }
                                .accessibilityLabel(NSLocalizedString("Choose Cover Image", comment: "Accessibility label for choose cover image button"))
                        }
                        Spacer()
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField(NSLocalizedString("Title", comment: "Title field placeholder"), text: $title)
                            .focused($titleFieldFocused)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.sentences)
                            .accessibilityLabel(NSLocalizedString("Title", comment: "Accessibility label for title field"))
                            .onSubmit {
                                if isTitleValid {
                                    descriptionFieldFocus = true
                                }
                            }
                        
                        if !isTitleValid && !title.isEmpty {
                            Text(NSLocalizedString("Title is required", comment: "Error message for empty title"))
                                .foregroundColor(.red)
                                .font(.caption)
                                .accessibilityLabel(NSLocalizedString("Title is required", comment: "Accessibility label for title error message"))
                        }
                    }
                    
                    TextEditor(text: $descriptionText)
                        .frame(minHeight: 80, maxHeight: 150)
                        .accessibilityLabel(NSLocalizedString("Description", comment: "Accessibility label for description field"))
                }
            }
            .navigationTitle(NSLocalizedString("New Playlist", comment: "Navigation title for new playlist view"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(NSLocalizedString("Cancel", comment: "Cancel button"))
                    }
                    .accessibilityLabel(NSLocalizedString("Cancel", comment: "Accessibility label for cancel button"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveTapped()
                    } label: {
                        Text(NSLocalizedString("Save", comment: "Save button"))
                    }
                    .disabled(!isTitleValid || isSaving)
                    .accessibilityLabel(NSLocalizedString("Save Playlist", comment: "Accessibility label for save button"))
                }
            }
            .alert(NSLocalizedString("Error", comment: "Alert title for error"), isPresented: Binding(get: {
                errorMessage != nil
            }, set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            })) {
                Button(NSLocalizedString("OK", comment: "OK button")) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: photoItem) { oldItem, newItem in
                Task {
                    if let item = newItem {
                        do {
                            if let data = try await item.loadTransferable(type: Data.self) {
                                selectedImageData = data
                            }
                        } catch {
                            print("Failed to load selected image data: \(error.localizedDescription)")
                        }
                    } else {
                        selectedImageData = nil
                    }
                }
            }
            .imagePlaygroundSheet(isPresented: $isShowingPlayground, concept: title) { url in
                if let data = try? Data(contentsOf: url) {
                    selectedImageData = data
                }
            }
            .imagePlaygroundGenerationStyle(.illustration)
        }
    }
    
    @FocusState private var descriptionFieldFocus: Bool

    private func saveTapped() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = NSLocalizedString("Title is required", comment: "Error message for empty title")
            return
        }
        
        isSaving = true
        
        // Note: imageRef is nil here as integration with Image Playground is a dependency and not implemented (TICKET-DM001).
        do {
            try modelContext.createPlaylist(
                title: trimmed,
                description: descriptionText,
                imageRef: nil,
                imageData: selectedImageData,
                tracks: []
            )
            onSuccess(trimmed)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isSaving = false
    }
}

#Preview {
    NewPlaylistView { _ in }
        .modelContainer(for: Playlist.self, inMemory: true)
}

