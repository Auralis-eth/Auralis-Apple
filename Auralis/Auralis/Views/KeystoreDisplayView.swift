//
//  KeystoreDisplayView.swift
//  KickingHorse
//
//  Created by Daniel Bell on 8/24/24.
//

import SwiftUI
import web3

struct KeystoreDisplayView: View {
    let keystore: EthereumKeyStore
    @Binding var network: EthereumNetwork
    @Environment(\.modelContext) private var mc

    var body: some View {

        if let nickName = keystore.nickName {
            GroupBox {
                VStack {
                    ForEach(keystore.addresses) { ethAddress in
                        GroupBox {
                            AddressDisplayView(network: $network, ethAddress: ethAddress, keystore: keystore)
                        }
//                        .draggable(ETHAddressTransferable(privateKey: ethAddress.privateKey, address: ethAddress.ethereumAddress)) {
//                            Text(ethAddress.address)
//                        }
                        .contextMenu {
                            //like Button, Toggle, and Picker
                            Button {
                                // Add this item to a list of favorites.
                            } label: {
                                Label("Add to Favorites", systemImage: "heart")
                            }
                        } preview: {
                            Color.red
                        }
                    }
                }
            } label: {
                Label(nickName, systemImage: "lock.square")
            }
//            .dropDestination(for: ETHAddressTransferable.self) { items, location in
//                items.forEach { item in
//                    guard !keystore.addresses.contains(where: {address in address.address ==  item.address.asString()}) else {
//                        return
//                    }
//                    if let data = item.privateKey {
//                        do {
//                            try keystore.storePrivateKey(key: data, with: item.address)
//                        } catch {
//                            fatalError("not implemented"+(error as NSError).localizedDescription)
//                        }
//                    } else {
//                        fatalError("not implemented")
//                    }
//                }
//
//                try? mc.save()
//                return true
//            }
            .contextMenu {
                //like Button, Toggle, and Picker
                Button {
                    // Add this item to a list of favorites.
                } label: {
                    Label("Add to Favorites", systemImage: "heart")
                }
            } preview: {
                Color.red
            }

        } else {
            GroupBox {
                VStack {
                    ForEach(keystore.addresses) { ethAddress in
                        GroupBox {
                            AddressDisplayView(network: $network, ethAddress: ethAddress, keystore: keystore)
                        }
//                        .draggable(ETHAddressTransferable(privateKey: ethAddress.privateKey, address: ethAddress.ethereumAddress)) {
//                            Text(ethAddress.address)
//                        }
                        .contextMenu {
                            //like Button, Toggle, and Picker
                            Button {
                                // Add this item to a list of favorites.
                            } label: {
                                Label("Add to Favorites", systemImage: "heart")
                            }
                        } preview: {
                            Color.red
                        }
                    }
                }
            }
//            .dropDestination(for: ETHAddressTransferable.self) { items, location in
//                items.forEach { item in
//                    guard !keystore.addresses.contains(where: {address in address.address ==  item.address.asString()}) else {
//                        return
//                    }
//                    if let data = item.privateKey {
//                        do {
//                            try keystore.storePrivateKey(key: data, with: item.address)
//                        } catch {
//                            fatalError("not implemented"+(error as NSError).localizedDescription)
//                        }
//                    } else {
//                        fatalError("not implemented")
//                    }
//                }
//
//                try? mc.save()
//                return true
//            }
            .contextMenu {
                //like Button, Toggle, and Picker
                Button {
                    // Add this item to a list of favorites.
                } label: {
                    Label("Add to Favorites", systemImage: "heart")
                }
            } preview: {
                Color.red
            }
        }
    }
}
//#Preview {
//    KeystoreDisplayView()
//}
