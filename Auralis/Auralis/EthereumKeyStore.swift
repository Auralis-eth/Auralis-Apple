//
//  EthereumKeyStore.swift
//  KickingHorse
//
//  Created by Daniel Bell on 8/2/24.
//

import Foundation
import web3
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

//TODO: Strategy
//1. base level has privateKey data stored directly
//2. simple keychain storage
//3. biometrics


@Model
final class ETHAddress: Identifiable, Hashable {
    @Attribute(.unique) var address: String
    var privateKey: Data?
    var keyStore: EthereumKeyStore?
    var nickName: String?

    @Transient var access: Bool {
        privateKey != nil
    }

    var id: String {
        address
    }

    init(address: String, privateKey: Data?, keyStores: EthereumKeyStore?) {
        self.address = address
        self.keyStore = keyStores
        self.privateKey = privateKey

    }

    enum CodingKeys: CodingKey {
        case address
        case privateKey
    }

    var ethereumAddress: EthereumAddress {
        EthereumAddress(address)
    }

    func resetPrivateKey() {
        privateKey = nil
    }
}

@Model
class EthereumKeyStore {
    @Relationship(inverse: \ETHAddress.keyStore) var addresses: [ETHAddress]
    var nickName: String?
    init(addresses: [ETHAddress] = []) {
        self.addresses = addresses
    }
}

extension EthereumKeyStore: EthereumMultipleKeyStorageProtocol {

    public func fetchAccounts() throws -> [EthereumAddress] {
        addresses.map { $0.ethereumAddress }
    }

    public func storePrivateKey(key: Data, with address: EthereumAddress) throws {
        let ethAddress = ETHAddress(address: address.asString(), privateKey: key, keyStores: nil)
        addresses.append(ethAddress)
    }

    public func loadPrivateKey(for address: EthereumAddress) throws -> Data {
        guard let ethAddress = addresses.filter({ $0.address == address.asString() }).first else {
            throw EthereumKeyStorageError.notFound
        }

        guard let data = ethAddress.privateKey else {
            throw EthereumKeyStorageError.failedToLoad
        }

        return data//Keyring.loadEntry(key: data.keychainKey) ?? Data()
    }

    public func deleteAllKeys() throws {
        addresses = []
//        KeyChain().deleteAllWalletData()
    }

    public func deletePrivateKey(for address: EthereumAddress) throws {
        addresses = addresses.filter { $0.address != address.asString() }
//        KeyChain().deleteWalletData(key: address.asString())
    }
}
