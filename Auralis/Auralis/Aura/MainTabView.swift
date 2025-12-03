import SwiftUI

struct MainTabView: View {
    @Binding var currentAccount: EOAccount?
    @Binding var currentAddress: String
    @Binding var currentChainId: String
    @Binding var currentChain: Chain
    @Binding var nftService: NFTService
    let audioEngine: AudioEngine

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                HomeTabView(
                    currentAccount: $currentAccount,
                    currentAddress: $currentAddress,
                    currentChainId: $currentChainId
                )
            }

            Tab("NewsFeed", systemImage: "bubble.right") {
                NewsFeedView(currentAccount: $currentAccount, nftService: $nftService, currentChain: $currentChain)
            }

            Tab("Gas", systemImage: "fuelpump") {
                ZStack(alignment: .bottom) {
                    GatewayBackgroundImage()
                    Color.background.opacity(0.3)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                    GasPriceEstimateView(chain: $currentChain)
                }
            }

            Tab("Music", systemImage: "play.circle") {
                VStack {
                    NFTMusicPlayerApp(audioEngine: audioEngine)
                }
            }

            Tab("Profile", systemImage: "person.circle") {
                Text("SentView()")
                Text("ENS")
            }

            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                Button(action: {}) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.textPrimary)
                        .font(.headline)
                }

            }
        }
        .tint(.accent)
    }
}

// Preview scaffold (optional)
#Preview {
    // Provide simple placeholders/mocks for preview purposes
    struct Wrapper: View {
        @State private var currentAccount: EOAccount? = nil
        @State private var currentAddress: String = ""
        @State private var currentChainId: String = Chain.ethMainnet.rawValue
        @State private var currentChain: Chain = .ethMainnet
        @State private var nftService = NFTService()
        let audioEngine: AudioEngine = try! AudioEngine()

        var body: some View {
            MainTabView(
                currentAccount: $currentAccount,
                currentAddress: $currentAddress,
                currentChainId: $currentChainId,
                currentChain: $currentChain,
                nftService: $nftService,
                audioEngine: audioEngine
            )
        }
    }
    return Wrapper()
}
