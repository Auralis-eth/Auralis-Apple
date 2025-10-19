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
    @State private var isloading: Bool = false
    @State private var generatedImages: [UIImage]?
    
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
                    generatedImages = nil
                    Task { @MainActor in
                        try? await generateImage()
                    }
                }
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
        }
        .task {
            if generatedImages == nil {
                try? await generateImage()
            }
        }
    }
    
    func generateImage() async throws {
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
            print("Image creation not supported on the current device.")
        }
    }
}
