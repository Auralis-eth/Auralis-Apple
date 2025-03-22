//
//  AuralisApp.swift
//  Auralis
//
//  Created by Daniel Bell on 10/20/24.
//

import SwiftUI
import SwiftData
import metamask_ios_sdk

@main
struct AuralisApp: App {
    let appMetadata = AppMetadata(
        name: "Auralis.ETH",
        url: "Auralis.eth",//"https://dubdapp.com",
        iconUrl: "https://pbs.twimg.com/profile_images/1846931552753930242/on5jhKP6_400x400.jpg"
    )
    @ObservedObject var metamaskSDK: MetaMaskSDK
    @State var account: String = "0x183AbE67478eB7E87c96CA28E2f63Dec53f22E3A"

    @MainActor @preconcurrency init() {
        metamaskSDK = MetaMaskSDK.shared(
            appMetadata,
            transport: .socket,
            //sdkOptions: SDKOptions(infuraAPIKey: "your-api-key", readonlyRPCMap: ["0x1": "hptts://www.testrpc.com"]) // for read-only RPC calls
            sdkOptions: SDKOptions(infuraAPIKey: "your-api-key") // for read-only RPC calls
            )
    }

    var body: some Scene {
        //                    ParentView()
        WindowGroup {
            TabView {
                //TODO: extract chain
                WalletView(metamaskSDK: metamaskSDK, account: $account)
                    .onAppear {
                        account = "0x183AbE67478eB7E87c96CA28E2f63Dec53f22E3A"
                    }
                    .tabItem {
                        Image(systemName: "wallet.bifold.fill")
                        Text("Wallet")
                    }

                //TODO: fix UI
                NFTBrowserView(address: $account)
                    .tabItem {
                        Image(systemName: "location.north.circle")
                        Text("NFT Browser")
                    }

                GasPriceEstimateView()
                    .tabItem {
                        Image(systemName: "fuelpump")
                        Text("Gas")
                    }


            }
        }
        .modelContainer(for: [ETHAddress.self, EthereumKeyStore.self])
#if os(macOS)
        Settings {
            Text("Settings")
        }
        //MenuBarExtra(content: <#T##() -> _#>, label: <#T##() -> _#>)
        MenuBarExtra {
            Text("Settings")
        }.menuBarExtraStyle(.window)
#endif
    }
}

//struct AddressBarView: View {
//    @Binding var address: String
//    @State private var isLoading: Bool = false
//    var populateNFTs: (() async -> Void)? = nil
//
//    var body: some View {
//        HStack(spacing: 12) {
//            Image(systemName: "wallet.pass")
//                .foregroundColor(.secondary)
//                .font(.system(size: 16, weight: .medium))
//                .padding(.leading, 4)
//
//            TextField("Enter wallet address", text: $address)
//                .font(.system(size: 15))
//                .foregroundColor(.primary)
//                .autocapitalization(.none)
//                .disableAutocorrection(true)
//                .onSubmit {
//                    submitAddress()
//                }
//
//            Button {
//                submitAddress()
//            } label: {
//                Group {
//                    if isLoading {
//                        ProgressView()
//                            .progressViewStyle(CircularProgressViewStyle())
//                            .scaleEffect(0.8)
//                    } else {
//                        Image(systemName: "arrow.right.circle.fill")
//                            .font(.system(size: 20, weight: .semibold))
//                            .foregroundColor(.blue)
//                    }
//                }
//                .frame(width: 28, height: 28)
//            }
//            .buttonStyle(PlainButtonStyle())
//            .padding(.trailing, 4)
//        }
//        .padding(.vertical, 12)
//        .padding(.horizontal, 16)
//        .background(
//            RoundedRectangle(cornerRadius: 16)
//                .fill(Color(.systemBackground))
//                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
//        )
//        .overlay(
//            RoundedRectangle(cornerRadius: 16)
//                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
//        )
//        .padding(.horizontal, 16)
//        .padding(.vertical, 8)
//    }
//
//    private func submitAddress() {
//        guard !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
//
//        isLoading = true
//
//        Task {
//            await populateNFTs?()
//            isLoading = false
//        }
//    }
//}

struct WalletView: View {
    @ObservedObject var metamaskSDK: MetaMaskSDK
    @Binding var account: String
    var body: some View {
        VStack {
            AddressBarView(address: $account)

            if metamaskSDK.connected {
                Text(metamaskSDK.chainId)
                WalletButtonView(metamaskSDK: metamaskSDK, action: .disconnect)
            } else {
                WalletButtonView(metamaskSDK: metamaskSDK, action: .connect)
            }
        }
        .onChange(of: metamaskSDK.account, initial: true) {//oldState, newState in
            account = metamaskSDK.account
        }
        .onAppear {
            account = metamaskSDK.account
        }
    }
}

struct WalletButtonView: View {
    enum Action {
        case connect
        case disconnect
    }
    @ObservedObject var metamaskSDK: MetaMaskSDK
    let action: Action
    var body: some View {
        Button {
            Task {
                if action == .disconnect {
                    metamaskSDK.terminateConnection()
                } else {
                    _ = await metamaskSDK.connect()
                }
            }
        } label: {
            HStack {
                Image(systemName: "link")
                    .font(.system(size: 18))

                Text(action == .disconnect ? "Disconnect MetaMask" : "conect MetaMask")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.orange)
            .cornerRadius(10)
            .shadow(radius: 3)
        }
    }
}

struct AddressBarView: View {
    @Binding var address: String
    @State private var isLoading: Bool = false
    @State private var isEditing: Bool = false
    var populateNFTs: (() async -> Void)? = nil

    // Format the address for display (abbreviated)
    private var displayAddress: String {
        if !isEditing && address.count > 10 {
            let start = address.prefix(6)
            let end = address.suffix(4)
            return "\(start)...\(end)"
        }
        return address
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wallet.pass")
                .foregroundColor(.secondary)
                .font(.system(size: 16, weight: .medium))
                .padding(.leading, 4)

            if isEditing {
                // Full address when editing
                TextField("Enter wallet address", text: $address)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onSubmit {
                        isEditing = false
                        submitAddress()
                    }
                    .onAppear {
                        // Ensure keyboard is shown when editing starts
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            UIApplication.shared.sendAction(#selector(UIResponder.becomeFirstResponder), to: nil, from: nil, for: nil)
                        }
                    }
            } else {
                // Abbreviated address when not editing
                Text(displayAddress)
                    .font(.system(size: 15))
                    .foregroundColor(.primary)
                    .onTapGesture {
                        isEditing = true
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                if isEditing {
                    isEditing = false
                }
                submitAddress()
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.blue)
                    }
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.trailing, 4)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func submitAddress() {
        guard !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isLoading = true

        Task {
            await populateNFTs?()
            isLoading = false
        }
    }
}
