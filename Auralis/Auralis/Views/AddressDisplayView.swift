//
//  AddressDisplayView.swift
//  KickingHorse
//
//  Created by Daniel Bell on 8/24/24.
//

import SwiftUI
import web3

struct AddressDisplayView: View {
    @State private var balance: String?
    @Binding var network: EthereumNetwork
    let ethAddress: ETHAddress
    let keystore: EthereumKeyStore
    var body: some View {
        VStack {
            ViewThatFits {
                Text(ethAddress.nickName ?? ethAddress.address.addressFormatedForDisplay())
                    .lineLimit(1, reservesSpace: true)
                Text(ethAddress.nickName ?? ethAddress.address)
                    .lineLimit(1, reservesSpace: true)
                    .truncationMode(.middle)
            }
            if let balance {
                HStack {
                    Text("Balance:")
                    Spacer()
                    Text(balance)
                }
            }
        }
        .task {
            do {
                let clientUrl = "https://sepolia.infura.io/v3/fa75668c9d754309ae8e1c8507de6d32"
                guard let url = URL(string: clientUrl) else { return }
                let client = EthereumHttpClient(url: url, network: network)
                let account1 =  try EthereumAccount(addressString: ethAddress.address, keyStorage: keystore, keystorePassword: "web3swift_0")
                let balance = try await client.eth_getBalance(address: account1.address , block: .Latest)
                self.balance = balance.description
            } catch {
                print(error)
            }
        }
    }
}

struct BasicAddressDisplayView: View {
    let ethAddress: ETHAddress
    var body: some View {
        VStack {
            ViewThatFits {
                Text(ethAddress.nickName ?? ethAddress.address.addressFormatedForDisplay())
                    .lineLimit(1, reservesSpace: true)
                Text(ethAddress.nickName ?? ethAddress.address)
                    .lineLimit(1, reservesSpace: true)
                    .truncationMode(.middle)
            }
        }
        .contentShape(Rectangle())
//        .task {
//            let addressString = ethAddress.address
//            let abc = await Moralis().transctions(for: addressString)
//            print(abc)
//        }
    }
}

struct BasicAddressEditorView: View {
    let ethAddress: ETHAddress
    @State private var nickname: String = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack {
            ViewThatFits {
                Text(ethAddress.address.addressFormatedForDisplay())
                    .lineLimit(1, reservesSpace: true)
                Text(ethAddress.address)
                    .lineLimit(1, reservesSpace: true)
                    .truncationMode(.middle)
            }
            if let privateKey = ethAddress.privateKey?.web3.hexString {
                Text(privateKey)
                    .privacySensitive(true)
                ScrollView {
                    Text(privateKey)
                        .redacted(reason: .privacy)
                }
            }
            Form {
                TextField("nickname", text: $nickname)
//                var privateKey: Data?

            }
            .padding()
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(ethAddress.access ? .gray : .orange, lineWidth: ethAddress.access ? 1 : 5)
            )
            Button("save") {
                save()
            }
        }
        .onAppear {
            nickname = ethAddress.nickName ?? nickname
        }
        .onSubmit {
            save()
        }
    }
    func save() {
        ethAddress.nickName = nickname
        dismiss()
    }
}
//#Preview {
//    AddressDisplayView()
//}
