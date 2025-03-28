//
//  DataModels.swift
//  KickingHorse
//
//  Created by Daniel Bell on 8/24/24.
//

import Foundation


struct WalletHistoryResponse: Codable {
    let pageSize: Int
    let cursor: String?
    let page: Int
    var result: [WalletHistoryResult]

    enum CodingKeys: String, CodingKey {
        case page
        case pageSize = "page_size"
        case cursor, result
    }
}

// MARK: - Result
struct WalletHistoryResult: Codable, Identifiable {
    var id: String {
        hash + nonce + blockTimestamp + blockNumber + blockHash + transactionIndex
    }

    let hash: String
    let nonce: String
    let fromAddress: String
    let transactionIndex: String
    let fromAddressLabel: String?
    let toAddressLabel: String?
    let toAddress, value: String
    let input: String?
    let gas, gasPrice, receiptCumulativeGasUsed: String
    let receiptContractAddress: String?
    let receiptRoot: String?
    let receiptGasUsed, receiptStatus: String
    let blockTimestamp, blockNumber, blockHash: String
    let logs: [String]?
    let internalTransactions: [InternalTransaction]?
    let nftTransfers: [NftTransfer]?
    let erc20Transfer: [Erc20Transfer]?
    let nativeTransfers: [NativeTransfer]?

    enum CodingKeys: String, CodingKey {
        case hash, nonce
        case transactionIndex = "transaction_index"
        case fromAddress = "from_address"
        case fromAddressLabel = "from_address_label"
        case toAddress = "to_address"
        case toAddressLabel = "to_address_label"
        case value, gas
        case gasPrice = "gas_price"
        case input
        case receiptCumulativeGasUsed = "receipt_cumulative_gas_used"
        case receiptGasUsed = "receipt_gas_used"
        case receiptContractAddress = "receipt_contract_address"
        case receiptRoot = "receipt_root"
        case receiptStatus = "receipt_status"
        case blockTimestamp = "block_timestamp"
        case blockNumber = "block_number"
        case blockHash = "block_hash"
        case logs
        case internalTransactions = "internal_transactions"
        case nftTransfers = "nft_transfers"
        case erc20Transfer = "erc20_transfer"
        case nativeTransfers = "native_transfers"
    }
}

struct WalletNFTResponse: Codable {
    let status: String?
    let total: String?
    let page: Int?
    let pageSize: String?
    let cursor: String?
    let result: [NFT]?
}

// MARK: - Erc20Transfer
struct Erc20Transfer: Codable {
    let tokenName, tokenSymbol: String
    let tokenLogo: String
    let tokenDecimals, transactionHash, address, blockTimestamp: String
    let blockNumber, blockHash, toAddress, toAddressLabel: String
    let fromAddress, fromAddressLabel, value: String
    let transactionIndex, logIndex: Int
    let possibleSpam, verifiedContract: String

    enum CodingKeys: String, CodingKey {
        case tokenName = "token_name"
        case tokenSymbol = "token_symbol"
        case tokenLogo = "token_logo"
        case tokenDecimals = "token_decimals"
        case transactionHash = "transaction_hash"
        case address
        case blockTimestamp = "block_timestamp"
        case blockNumber = "block_number"
        case blockHash = "block_hash"
        case toAddress = "to_address"
        case toAddressLabel = "to_address_label"
        case fromAddress = "from_address"
        case fromAddressLabel = "from_address_label"
        case value
        case transactionIndex = "transaction_index"
        case logIndex = "log_index"
        case possibleSpam = "possible_spam"
        case verifiedContract = "verified_contract"
    }
}

// MARK: - InternalTransaction
struct InternalTransaction: Codable {
    let transactionHash, blockNumber, blockHash, type: String
    let from, to, value, gas: String
    let gasUsed, input, output: String

    enum CodingKeys: String, CodingKey {
        case transactionHash = "transaction_hash"
        case blockNumber = "block_number"
        case blockHash = "block_hash"
        case type, from, to, value, gas
        case gasUsed = "gas_used"
        case input, output
    }
}

// MARK: - NativeTransfer
struct NativeTransfer: Codable {
    let fromAddressLabel: String?
    let toAddressLabel: String?
    let internalTransaction: Bool?
    let fromAddress, toAddress: String
    let value, valueFormatted, direction: String
    let tokenSymbol: String
    let tokenLogo: String

    enum CodingKeys: String, CodingKey {
        case fromAddress = "from_address"
        case fromAddressLabel = "from_address_label"
        case toAddress = "to_address"
        case toAddressLabel = "to_address_label"
        case value
        case valueFormatted = "value_formatted"
        case direction
        case internalTransaction = "internal_transaction"
        case tokenSymbol = "token_symbol"
        case tokenLogo = "token_logo"
    }
}

// MARK: - NftTransfer
struct NftTransfer: Codable {
    let tokenAddress, tokenID, fromAddress: String
    let fromAddressLabel: String?
    let toAddressLabel: String?
    let toAddress, value, amount: String
    let contractType: String
    let blockTimestamp: String?
    let blockHash: String?
    let blockNumber: String?
    let transactionType: String
    let transactionHash: String?
    let transactionIndex: Int?
    let logIndex: Int
    let nftTransferOperator: String?
    let possibleSpam: Bool?
    let verifiedCollection: Bool?

    enum CodingKeys: String, CodingKey {
        case tokenAddress = "token_address"
        case tokenID = "token_id"
        case fromAddress = "from_address"
        case fromAddressLabel = "from_address_label"
        case toAddress = "to_address"
        case toAddressLabel = "to_address_label"
        case value, amount
        case contractType = "contract_type"
        case blockNumber = "block_number"
        case blockTimestamp = "block_timestamp"
        case blockHash = "block_hash"
        case transactionHash = "transaction_hash"
        case transactionType = "transaction_type"
        case transactionIndex = "transaction_index"
        case logIndex = "log_index"
        case nftTransferOperator = "operator"
        case possibleSpam = "possible_spam"
        case verifiedCollection = "verified_collection"
    }
}
