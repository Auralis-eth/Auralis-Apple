import SwiftUI
import UIKit
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
    @State private var isProcessingImage: Bool = false
    
    @State private var sourceMenuPresented: Bool = false
    @State private var showCameraSheet: Bool = false
    @State private var showPhotoPickerSheet: Bool = false
    @State private var shouldLaunchPlaygroundAfterPick: Bool = false
    @State private var capturedImage: UIImage? = nil
    
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
                            Button {
                                sourceMenuPresented = true
                            } label: {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.secondary.opacity(0.1))
                                    .frame(width: 150, height: 150)
                                    .overlay(
                                        Image(systemName: "camera")
                                            .font(.system(size: 50))
                                            .foregroundColor(.secondary)
                                    )
                                    .accessibilityLabel(NSLocalizedString("No Cover Image Selected", comment: "Accessibility label for no cover image"))
                            }
                            .contextMenu {
                                Button {
                                    startFromCamera()
                                } label: {
                                    Label(NSLocalizedString("Start from Camera", comment: "Context menu option to start from camera"), systemImage: "camera")
                                }
                                Button {
                                    startFromPhoto()
                                } label: {
                                    Label(NSLocalizedString("Start from Photo", comment: "Context menu option to start from photo"), systemImage: "photo")
                                }
                                Button {
                                    startFromBlank()
                                } label: {
                                    Label(NSLocalizedString("Start from Blank", comment: "Context menu option to start from blank"), systemImage: "sparkles")
                                }
                            }
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
            .overlay(alignment: .center) {
                if isProcessingImage {
                    ProgressView(NSLocalizedString("Processing…", comment: "Progress while processing image"))
                        .padding(16)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel(NSLocalizedString("Processing", comment: "Accessibility label for processing indicator"))
                }
            }
            .disabled(isProcessingImage)
            .navigationTitle(NSLocalizedString("New Playlist", comment: "Navigation title for new playlist view"))
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(NSLocalizedString("Start From", comment: "Title for source selection dialog"), isPresented: $sourceMenuPresented, titleVisibility: .visible) {
                Button(NSLocalizedString("Start from Camera", comment: "Dialog option")) { startFromCamera() }
                Button(NSLocalizedString("Start from Photo", comment: "Dialog option")) { startFromPhoto() }
                Button(NSLocalizedString("Start from Blank", comment: "Dialog option")) { startFromBlank() }
                Button(NSLocalizedString("Cancel", comment: "Cancel button"), role: .cancel) { }
            }
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
            .photosPicker(isPresented: $showPhotoPickerSheet, selection: $photoItem, matching: .images, photoLibrary: .shared())
            .sheet(isPresented: $showCameraSheet) {
                ImagePicker(image: $capturedImage, sourceType: .camera)
                    .ignoresSafeArea()
            }
            .onChange(of: capturedImage) { _, newImage in
                isProcessingImage = true
                defer { isProcessingImage = false }
                if let uiImage = newImage, let data = uiImage.jpegData(compressionQuality: 0.9) {
                    selectedImageData = data
                    isShowingPlayground = true
                }
            }
            .onChange(of: photoItem) { oldItem, newItem in
                Task {
                    isProcessingImage = true
                    defer { isProcessingImage = false }
                    if let item = newItem {
                        do {
                            if let data = try await item.loadTransferable(type: Data.self) {
                                selectedImageData = data
                                if shouldLaunchPlaygroundAfterPick {
                                    isShowingPlayground = true
                                    shouldLaunchPlaygroundAfterPick = false
                                }
                            }
                        } catch {
                            print("Failed to load selected image data: \(error.localizedDescription)")
                        }
                    } else {
                        selectedImageData = nil
                    }
                }
            }
            .imagePlaygroundSheet(isPresented: $isShowingPlayground, concept: title, sourceImage: sourceImage) { url in
                if let data = try? Data(contentsOf: url) {
                    selectedImageData = data
                }
            }
            .imagePlaygroundGenerationStyle(.illustration)
        }
    }
    
    var sourceImage: Image? {
        guard let selectedImageData else { return nil }
        guard let image = UIImage(data: selectedImageData) else { return nil }
        return Image(uiImage: image)
    }
    
    @FocusState private var descriptionFieldFocus: Bool

    private func startFromCamera() {
        showCameraSheet = true
    }

    private func startFromPhoto() {
        shouldLaunchPlaygroundAfterPick = true
        showPhotoPickerSheet = true
    }

    private func startFromBlank() {
        isShowingPlayground = true
    }
    
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

struct ImagePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType = .photoLibrary

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let img = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                parent.image = img
            }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
