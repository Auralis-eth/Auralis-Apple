//
//  EthereumKeyStoreDetailView.swift
//  KickingHorse
//
//  Created by Daniel Bell on 8/24/24.
//

import SwiftUI
//    .task {
//        //Open Sea
//        //0x0000000000000068F116a894984e2DB1123eB395
//
//        //Blur V2
//        //0x39da41747a83aeE658334415666f3EF92DD0D541
//
//        //Blur V3
//        //0xb2ecfE4E4D61f8790bbb9DE2D1259B9e2410CEA5
//
//        //Reservoir: Reservoir V6.0.1
//        //0xC2c862322E9c97D6244a3506655DA95F05246Fd8
//
//        //contract 1
//        //0xEF0B56692F78A44CF4034b07F80204757c31Bcc9
//
//        //cryptopuncks c token
//        //0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB
//
//        //Mine
//        //0xb713338a3986312774cF274931802eD6Ea94bA93
//
//        //has ENS
//        //0x3FB65FEEAB83bf60B0D1FfBC4217d2D97a35C8D4
//        //0x8Fc87c199203332c1cc43430b9FaD2B1868E44D0
//        //0x2e9A18d66f2FC535497cFB395D7F1BCb6746E582
//        //0xED6c7eF2ECFDe753c634f5917f48eF80F99BC9A0
//        //0x020cA66C30beC2c4Fe3861a94E4DB4A498A35872
//        //0x6599f83c1B154E2eC8229Fb12C9057e236705Db2
//        //0xDcfC30125bDF514B7c434f9868783C7B48D7a3BC
//        //0x4f6F6b4EACff3e96C19D8773ac5ac05F5a650207
//        //0x6A8bC66Bb56bDDdCC43b5e976A728D864C2aa4a4
//        //0x6A8bC66Bb56bDDdCC43b5e976A728D864C2aa4a4
//        //0x6B4039B0cA00F5ee82dd192BeD0cEe04A44D6010
//        //0xeBB51549bA3ea57CE52b60899edA9A97959Bd578
//        //0x54FAAd784C3aDDEF84aDeCaA5Ee30D3eD9aBcF20
//        //0x5099249b903299D831EDe682b2431334cfeF7C5e
//
//
//        //random
//        //0x69Df823fd57d8794a4dA3DF6fAEb0A5DdAEaFF78
//        //0xcC2a855946a3C20683858FE6eE15acF8B836f0b3    has value
//        //0x37FAE0b10Fb3e27031fd64E51693366B81D0cB95
//        //0x3820c123Ca814d9e05C46F30E3b7BB3BAB905af5    has ETH
//        //0xBddE90bA3266db04FCBa62a779615562A551876c    has ETH
//        //0xE3d3D0eD702504e19825f44BC6542Ff2ec45cB9A    has some value
//        //0x3664ad19fA7766DCf2bb97BAA9f0671401FfA814
//        //0x36a8169ECd533FDE80EE458937dbb954A877E08e
//        //0xCa6798217DdA9635ed7D370325843b45d468b249
//
//
//        //from API docs
//        //0xd8da6bf26964af9d7eed9e03e53415d37aa96045
////                    let abc = await Moralis().transctions(for: "0xCa6798217DdA9635ed7D370325843b45d468b249")
////                    print(abc)
//    }
struct EthereumKeyStoreDetailView: View {
    @Environment(\.modelContext) private var mc
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    let keystore: EthereumKeyStore
    @State var selectedKeystore: EthereumKeyStore?

    @State var transactionBook: [ETHAddress : WalletHistoryResponse]?
    @State private var sortOrder = [KeyPathComparator(\Result.blockNumber)]
    @State private var selection: Set<Result.ID> = []
    var transactions: [Result]? {
        guard let transactionBook else {
            return nil
        }
        var partialResult = [Result]()
        for next in transactionBook.values {
            partialResult.append(contentsOf: next.result)
        }

        partialResult.sort(using: sortOrder)
        partialResult = Array(partialResult.prefix(10))

        return partialResult
    }

    var body: some View {
        VStack {
            Text(keystore.nickName ?? "nickName")
                .navigationTitle(Text(keystore.nickName ?? "nickName"))
            if let transactions {
                if transactions.isEmpty {
                    ContentUnavailableView(
                        "No Transactions yet",
                        systemImage: "nosign",
                        description: Text("No Transactions yet")
                    )
                } else if verticalSizeClass == .regular && horizontalSizeClass == .regular {
                    Table(transactions, selection: $selection, sortOrder: $sortOrder){
                        TableColumn("blockNumber", value: \.blockNumber)
                        TableColumn("from", value: \.fromAddress)
                        TableColumn("fromAddressLabel") { transtaction in
                            Text(transtaction.fromAddressLabel ?? "")
                        }
                        TableColumn("toAddressLabel") { transtaction in
                            Text(transtaction.toAddressLabel ?? "")
                        }
                        TableColumn("toAddress", value: \.toAddress)
//                        TableColumn("logs", value: \.logs)
                        TableColumn("input") { transtaction in
                            Text(transtaction.input ?? "")
                        }
                    }
                    .contextMenu(forSelectionType: Result.ID.self) { items in
                        Button("Delete") {
                            print("Delete")
                        }
                    }
                } else {
                    ScrollView {
                        ForEach(transactions) { transaction in
                            VStack {
                                Text(transaction.blockNumber)
                                VStack {
                                    VStack {
                                        if let fromAddressLabel = transaction.fromAddressLabel {
                                            Text(fromAddressLabel)
                                        }
                                        ViewThatFits {
                                            Text(transaction.fromAddress.addressFormatedForDisplay())
                                                .lineLimit(1, reservesSpace: true)
                                            Text(transaction.fromAddress)
                                                .lineLimit(1, reservesSpace: true)
                                                .truncationMode(.middle)
                                        }
                                    }

                                    VStack {
                                        if let toAddressLabel = transaction.toAddressLabel {
                                            Text(toAddressLabel)
                                        }
                                        ViewThatFits {
                                            Text(transaction.toAddress.addressFormatedForDisplay())
                                                .lineLimit(1, reservesSpace: true)
                                            Text(transaction.toAddress)
                                                .lineLimit(1, reservesSpace: true)
                                                .truncationMode(.middle)
                                        }
                                    }
                                }
                                if let input = transaction.input {
                                    Text(input)
                                }
                                if let logs = transaction.logs {
                                    ForEach(logs, id: \.self) { log in
                                        Text(log)
                                    }
                                }
                            }
//                            let logs: [String]?
                        }
                    }
                }
            }
            ForEach(keystore.addresses) { address in
                VStack {
                    Text(address.nickName ?? "--")
                    Text(address.address)
                    if let transaction = transactionBook?[address]?.result.first {
                        Text(transaction.blockNumber)
                    }
                    
                }
            }
            //gear icon in top nav opens window to this content
            //        VStack {
            //            TextField("vault Name", text: keystore.nickName)//KeystoreTitle, keystoreVaultName
            //            ForEach(keystore.addresses) { address in
            //                TextField("Account Handle", text: address.nickName)//AccountTitle
            //            }
            //        }
            //        .onSubmit {
            //            mc.save()
            //        }
        }
        .sheet(item: $selectedKeystore) { keystore in
            KeystoreEditorView(keystore: keystore)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
//                    Button("Add Wallet", systemImage: "plus", action: addWallet)
                    Button("Keystore/Vault Setting", systemImage: "square.and.arrow.down") {
                        selectedKeystore = keystore
                    }
                } label: {
                    Image(systemName: "gear")
                        .imageScale(.large)
                } primaryAction: {
                    selectedKeystore = keystore
                }
            }
        }
        .task {
            await withTaskGroup(of: (ETHAddress, WalletHistoryResponse?).self) { group in
                for ethAddress in keystore.addresses {
                    group.addTask {
                        let transactions = await Moralis().transctions(for: ethAddress.address)
                        return (ethAddress, transactions)
                    }
                }

                for await (address, transactions) in group {
                    guard let transactions else {
                        continue
                    }

                    if transactionBook == nil {
                        transactionBook = [address : transactions]
                    } else {
                        transactionBook?[address] = transactions
                    }
                }
            }
        }
    }
}

struct KeystoreEditorView: View {
    let keystore: EthereumKeyStore
    @State private var nickname: String = ""
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAddress: ETHAddress?
    var body: some View {
        VStack {
            Form {
                TextField("nickname", text: $nickname)
                ForEach(keystore.addresses) { address in
                    BasicAddressDisplayView(ethAddress: address)
                        .onTapGesture {
                            selectedAddress = address
                        }
                }
            }
            Button("save") {
                save()
            }
        }
        .onAppear {
            nickname = keystore.nickName ?? nickname
        }
        .onSubmit {
            save()
        }
        .sheet(item: $selectedAddress) { address in
            BasicAddressEditorView(ethAddress: address)
        }
    }
    func save() {
        keystore.nickName = nickname
        dismiss()
    }
}
//#Preview {
//    EthereumKeyStoreDetailView()
//}
