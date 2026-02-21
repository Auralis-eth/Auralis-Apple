import SwiftUI

// Represents each tab in the main TabView
enum AppTab: Hashable {
    case home
    case news
    case gas
    case music
    case profile
    case search
    case tokens
    case reciepts
}

struct MainTabView: View {
    @Binding var currentAccount: EOAccount?
    @Binding var currentAddress: String
    @Binding var currentChainId: String
    @Binding var currentChain: Chain
    @Binding var nftService: NFTService
    @Binding var selectedTab: AppTab
    let audioEngine: AudioEngine

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                HomeTabView(
                    currentAccount: $currentAccount,
                    currentAddress: $currentAddress,
                    currentChainId: $currentChainId,
                    selectedTab: $selectedTab
                )
            }

            Tab("NewsFeed", systemImage: "bubble.right", value: AppTab.news) {
                NewsFeedView(currentAccount: $currentAccount, nftService: $nftService, currentChain: $currentChain)
            }

            Tab("Gas", systemImage: "fuelpump", value: AppTab.gas) {
                ZStack(alignment: .bottom) {
                    GatewayBackgroundImage()
                    Color.background.opacity(0.3)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                    GasPriceEstimateView(chain: $currentChain)
                }
            }

            Tab("Music", systemImage: "play.circle", value: AppTab.music) {
                VStack {
                    NFTMusicPlayerApp(audioEngine: audioEngine)
                }
            }

            Tab("Profile", systemImage: "person.circle", value: AppTab.profile) {
                Text("SentView()")
                Text("ENS")
            }

            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
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
        @State private var selectedTab: AppTab = .home
        let audioEngine: AudioEngine = try! AudioEngine()

        var body: some View {
            MainTabView(
                currentAccount: $currentAccount,
                currentAddress: $currentAddress,
                currentChainId: $currentChainId,
                currentChain: $currentChain,
                nftService: $nftService,
                selectedTab: $selectedTab,
                audioEngine: audioEngine
            )
        }
    }
    return Wrapper()
}
