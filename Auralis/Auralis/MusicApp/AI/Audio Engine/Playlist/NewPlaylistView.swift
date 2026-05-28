import ImagePlayground
import MusicFeature
import OSLog
import PhotosUI
import ReceiptsCore
import ReceiptStorage
import SwiftData
import SwiftUI
import AuraUI
import UIKit

struct NewPlaylistView: View {
    private static let logger = Logger(subsystem: "Auralis", category: "NewPlaylistView")

    private enum PlaylistField: Hashable {
        case title
        case description
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var title: String = ""
    @State private var descriptionText: String = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    @State private var isShowingPlayground = false
    @State private var isProcessingImage: Bool = false
    @State private var coverSource: PlaylistCoverSource?

    @State private var sourceMenuPresented: Bool = false
    @State private var showCameraSheet: Bool = false
    @State private var showPhotoPickerSheet: Bool = false
    @State private var shouldLaunchPlaygroundAfterPick: Bool = false
    @State private var capturedImage: UIImage?

    let onSuccess: (String) -> Void

    @FocusState private var focusedField: PlaylistField?
    @AccessibilityFocusState private var focusedTitleError: Bool

    private enum PlaylistCoverSource {
        case camera
        case photoLibrary
        case generated

        var accessibilityDescription: String {
            switch self {
            case .camera:
                return String(localized: "From camera")
            case .photoLibrary:
                return String(localized: "From photo library")
            case .generated:
                return String(localized: "Generated")
            }
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isTitleValid: Bool {
        !trimmedTitle.isEmpty
    }

    private var processingBackground: AnyShapeStyle {
        reduceTransparency ? AnyShapeStyle(Color.surface) : AnyShapeStyle(.ultraThinMaterial)
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
                                .accessibilityLabel(String(localized: "Selected cover image"))
                                .accessibilityValue(coverSource?.accessibilityDescription ?? String(localized: "Source unknown"))
                        } else {
                            Button {
                                sourceMenuPresented = true
                            } label: {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.secondary.opacity(0.1))
                                    .frame(width: 150, height: 150)
                                    .overlay(
                                        SystemImage("camera")
                                            .font(.system(size: 50))
                                            .foregroundColor(.secondary)
                                            .accessibilityHidden(true)
                                    )
                            }
                            .accessibilityLabel(String(localized: "Choose playlist cover"))
                            .accessibilityValue(String(localized: "No cover selected"))
                            .accessibilityHint(String(localized: "Opens cover source options"))
                            .contextMenu {
                                Button {
                                    startFromCamera()
                                } label: {
                                    Label(String(localized: "Start from Camera"), systemImage: "camera")
                                }
                                Button {
                                    startFromPhoto()
                                } label: {
                                    Label(String(localized: "Start from Photo"), systemImage: "photo")
                                }
                                Button {
                                    startFromBlank()
                                } label: {
                                    Label(String(localized: "Start from Blank"), systemImage: "sparkles")
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
                            .accessibilityLabel(String(localized: "Generate cover art"))
                            .accessibilityHint(String(localized: "Opens Image Playground for this playlist cover"))
                            .accessibilityInputLabels([
                                String(localized: "Generate cover art"),
                                String(localized: "Create cover")
                            ])

                        } else {
                            PhotosPicker(
                                selection: $photoItem,
                                matching: .images,
                                photoLibrary: .shared()) {
                                    Text(String(localized: "Choose Cover"))
                                }
                                .accessibilityLabel(String(localized: "Choose Cover Image"))
                        }
                        Spacer()
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        TextField(String(localized: "Title"), text: $title)
                            .focused($focusedField, equals: .title)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.sentences)
                            .accessibilityLabel(String(localized: "Title"))
                            .onSubmit {
                                if isTitleValid {
                                    focusedField = .description
                                }
                            }

                        if !isTitleValid && !title.isEmpty {
                            Text(String(localized: "Title is required"))
                                .foregroundColor(.red)
                                .font(.caption)
                                .accessibilityLabel(String(localized: "Title is required"))
                                .accessibilityFocused($focusedTitleError)
                        }
                    }

                    TextEditor(text: $descriptionText)
                        .focused($focusedField, equals: .description)
                        .frame(
                            minHeight: dynamicTypeSize.isAccessibilitySize ? 160 : 80,
                            maxHeight: dynamicTypeSize.isAccessibilitySize ? nil : 150
                        )
                        .accessibilityLabel(String(localized: "Description"))
                }
            }
            .overlay(alignment: .center) {
                if isProcessingImage {
                    ProgressView(String(localized: "Processing..."))
                        .padding(16)
                        .background(processingBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel(String(localized: "Processing"))
                }
            }
            .disabled(isProcessingImage)
            .navigationTitle(String(localized: "New Playlist"))
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(String(localized: "Start From"), isPresented: $sourceMenuPresented, titleVisibility: .visible) {
                Button(String(localized: "Start from Camera")) { startFromCamera() }
                Button(String(localized: "Start from Photo")) { startFromPhoto() }
                Button(String(localized: "Start from Blank")) { startFromBlank() }
                Button(String(localized: "Cancel"), role: .cancel) { }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text(String(localized: "Cancel"))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saveTapped()
                    } label: {
                        Text(String(localized: "Save"))
                    }
                    .disabled(isSaving)
                }
            }
            .alert(String(localized: "Error"), isPresented: Binding(get: {
                errorMessage != nil
            }, set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            })) {
                Button(String(localized: "OK")) {
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
                    coverSource = .camera
                    AuraAccessibilityAnnouncer.announce(String(localized: "Playlist cover selected"))
                    isShowingPlayground = true
                }
            }
            .onChange(of: photoItem) { _, newItem in
                Task {
                    isProcessingImage = true
                    defer { isProcessingImage = false }
                    if let item = newItem {
                        do {
                            if let data = try await item.loadTransferable(type: Data.self) {
                                selectedImageData = data
                                coverSource = .photoLibrary
                                AuraAccessibilityAnnouncer.announce(String(localized: "Playlist cover selected"))
                                if shouldLaunchPlaygroundAfterPick {
                                    isShowingPlayground = true
                                    shouldLaunchPlaygroundAfterPick = false
                                }
                            }
                        } catch {
                            Self.logger.error("Failed to load selected image data: \(error.localizedDescription, privacy: .public)")
                            let message = String(localized: "Auralis could not load the selected image.")
                            errorMessage = message
                            AuraAccessibilityAnnouncer.announce(message)
                        }
                    } else {
                        selectedImageData = nil
                        coverSource = nil
                    }
                }
            }
            .imagePlaygroundSheet(isPresented: $isShowingPlayground, concept: title, sourceImage: sourceImage) { url in
                Task {
                    await loadGeneratedImage(from: url)
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
            let message = String(localized: "Title is required")
            errorMessage = message
            focusedField = .title
            focusedTitleError = true
            AuraAccessibilityAnnouncer.announce(message)
            return
        }

        isSaving = true
        let receiptLogger = MusicReceiptEventLogger(
            receiptStore: ReceiptStores.live(modelContext: modelContext)
        )

        Task {
            do {
                _ = try await modelContext.createPlaylist(
                    title: trimmed,
                    description: descriptionText,
                    imageRef: nil,
                    imageData: selectedImageData,
                    tracks: [],
                    musicReceiptLogger: receiptLogger,
                    receiptContext: MusicReceiptContext(
                        triggerCause: .userInitiated,
                        actor: .user,
                        surface: "music.playlist.new"
                    )
                )
                onSuccess(trimmed)
                dismiss()
            } catch {
                let message = error.localizedDescription
                errorMessage = message
                AuraAccessibilityAnnouncer.announce(message)
            }

            isSaving = false
        }
    }

    @MainActor
    private func loadGeneratedImage(from url: URL) async {
        isProcessingImage = true
        defer { isProcessingImage = false }

        do {
            let data = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: url)
            }.value
            selectedImageData = data
            coverSource = .generated
            AuraAccessibilityAnnouncer.announce(String(localized: "Playlist cover selected"))
        } catch {
            Self.logger.error("Failed to load generated playlist image: \(error.localizedDescription, privacy: .public)")
            let message = String(localized: "Auralis could not load the generated image.")
            errorMessage = message
            AuraAccessibilityAnnouncer.announce(message)
        }
    }
}

#Preview {
    NewPlaylistView { _ in }
        .modelContainer(PreviewModelContainers.primary())
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
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
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
