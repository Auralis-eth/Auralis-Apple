import SwiftUI
import SwiftData
import ImagePlayground

struct HomeTabView: View {
    @Binding var currentAccount: EOAccount?
    @Binding var currentAddress: String
    @Binding var currentChainId: String
    @Environment(\.modelContext) private var modelContext
    @Namespace var namespace
    let transitionID: String = "HomeTabView"
    @State private var isPresented: Bool = false
    @State private var presentDialog: Bool = false
    @State private var isLoading: Bool = false
    @State private var generatedImages: [UIImage]?
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert: Bool = false
    
    var body: some View {
        ZStack {
            if let firstImage = generatedImages?.randomElement() {
                Image(uiImage: firstImage)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            }
            
            VStack {
                Text("HELLO \(currentAccount?.address ?? "")")
                Button("Logout") {
                    try? modelContext.delete(model: NFT.self)
                    try? modelContext.delete(model: EOAccount.self)
                    try? modelContext.delete(model: Tag.self)
                    self.currentAccount = nil
                    currentAddress = ""
                    currentChainId = ""
                }
                Button("refresh UI") {
                    Task { @MainActor in
                        await generateImage()
                    }
                }
                .disabled(isLoading) // Disable refresh button when loading
            }
            .sheet(isPresented: $isPresented) {
                VStack {
                    Button(action: {
                        presentDialog = true
                    }, label: {
                        Text("hello")
                    })
                    .confirmationDialog("Delete?", isPresented: $presentDialog) {
                        Text("not deleted")
                    }
                }
                .navigationTransition(.zoom(sourceID: transitionID, in: namespace))
            }
            
            // Show placeholder when no images and not loading
            if (generatedImages == nil || generatedImages?.isEmpty == true) && !isLoading {
                ContentUnavailableView("No Images generated yet", systemImage: "photo.on.rectangle.angled")
                    .symbolRenderingMode(.hierarchical)
                    .background(.ultraThinMaterial)
            }
            
            // Overlay loading indicator blocking interaction
            if isLoading {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(2)
                    Text("Generating Images...")
                        .foregroundStyle(.white)
                        .font(.headline)
                        .padding(.top, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            if generatedImages == nil {
                await generateImage()
            }
        }
        .alert("Error", isPresented: $showErrorAlert, actions: {
            Button("Dismiss", role: .cancel) {
                showErrorAlert = false
            }
        }, message: {
            if let errorMessage = errorMessage {
                Text(errorMessage)
            }
        })
    }
    
    func generateImage() async {
        // Start loading and clear previous images
        isLoading = true
        defer { isLoading = false }
        generatedImages = nil
        
        do {
            let imageCreator = try await ImageCreator()
            
            let images = imageCreator.images(
                for: [.text("northern lights")],
                style: .illustration,
                limit: 3)
            
            for try await image in images {
                if let generatedImages = self.generatedImages {
                    self.generatedImages = generatedImages + [UIImage(cgImage: image.cgImage)]
                }
                else {
                    self.generatedImages = [UIImage(cgImage: image.cgImage)]
                }
            }
        }
        catch ImageCreator.Error.notSupported {
            errorMessage = "Image creation is not supported on this device."
            showErrorAlert = true
            return
        }
        catch {
            errorMessage = "Failed to generate images. Please try again.\n\(error.localizedDescription)"
            showErrorAlert = true
            return
        }
    }
}
