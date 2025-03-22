//
//  Chain.swift
//  Auralis
//
//  Created by Daniel Bell on 2/24/25.
//

// Define an enum for Chain IDs -  Refer to SimpleHash documentation for a comprehensive list
enum Chain: String, CaseIterable, Codable {
    case ethereum = "ethereum"
    case polygon = "polygon"
    case arbitrum = "arbitrum"
    case optimism = "optimism"
    case bsc = "bsc"
    case avalanche = "avalanche"
    case fantom = "fantom"
    case gnosis = "gnosis"
    case celo = "celo"
    case moonbeam = "moonbeam"
    case cronos = "cronos"
    case base = "base"
    case zora = "zora"
    case linea = "linea"
    case scroll = "scroll"
    case opBnb = "op_bnb"
    case solana = "solana"
    case bitcoin = "bitcoin"
    case xrpl = "xrp" // XRP Ledger uses "xrp" as chain name in simplehash
    case litecoin = "litecoin"
    case filecoin = "filecoin"
    case near = "near"
    case aptos = "aptos"
    case sui = "sui"
    case starknet = "starknet"
    case tezos = "tezos"
    case cosmos = "cosmos"
    case polkadot = "polkadot"
    case algorand = "algorand"
    case osmosis = "osmosis"
    case monero = "monero"
    case klaytn = "klaytn"
    case vechain = "vechain"
    case flow = "flow"
    case immutableX = "immutable_x" // needs underscore in rawValue
    case ronin = "ronin"
    case oasis = "oasis"
    case internetComputer = "internet_computer" // needs underscore in rawValue
    case cardano = "cardano"
    case eos = "eos"
    case theta = "theta"
    case hedera = "hedera"
    case stacks = "stacks"
    case ontology = "ontology"
    case wax = "wax"
    case harmony = "harmony"
    case fuse = "fuse"
    case canto = "canto"
    case aurora = "aurora"
    case kava = "kava"
    case secret = "secret"
    case moonriver = "moonriver"
    case metis = "metis"
    case telos = "telos"
    case okc = "okc"
    case conflux = "conflux"
    case nervos = "nervos"
    case iotex = "iotex"
    case qtum = "qtum"
    case syscoin = "syscoin"
    case ultron = "ultron"
    case elastos = "elastos"
    case findora = "findora"
    case horizen = "horizen"
    case oasisEmerald = "oasis_emerald" // needs underscore in rawValue
    case ton = "ton"
    case oasisSapphire = "oasis_sapphire" // needs underscore in rawValue
    case terra = "terra"
    case terraClassic = "terra_classic" // needs underscore in rawValue

    // Testnets
    /// Goerli test network (Ethereum)
    case goerli = "goerli"
    /// Sepolia test network (Ethereum)
    case sepolia = "sepolia"
    /// Mumbai test network (Polygon)
    case mumbai = "mumbai"
    case arbitrumGoerli = "arbitrum_goerli" // needs underscore in rawValue
    case optimismGoerli = "optimism_goerli" // needs underscore in rawValue
    case bscTestnet = "bsc_testnet" // needs underscore in rawValue
    /// Fuji test network (Avalanche)
    case fuji = "fuji"
    case fantomTestnet = "fantom_testnet" // needs underscore in rawValue
    case gnosisTestnet = "gnosis_testnet" // needs underscore in rawValue
    case alfajores = "alfajores"
    case moonbaseAlpha = "moonbase_alpha" // needs underscore in rawValue
    case cronosTestnet = "cronos_testnet" // needs underscore in rawValue
    case baseGoerli = "base_goerli" // needs underscore in rawValue
    case zoraGoerli = "zora_goerli" // needs underscore in rawValue
    case lineaGoerli = "linea_goerli" // needs underscore in rawValue
    case scrollSepolia = "scroll_sepolia" // needs underscore in rawValue
    case opBnbTestnet = "op_bnb_testnet" // needs underscore in rawValue
    case solanaTestnet = "solana_testnet" // needs underscore in rawValue
    case bitcoinTestnet = "bitcoin_testnet" // needs underscore in rawValue
    case xrplTestnet = "xrp_testnet" // needs underscore in rawValue
    case litecoinTestnet = "litecoin_testnet" // needs underscore in rawValue
    case filecoinTestnet = "filecoin_testnet" // needs underscore in rawValue
    case nearTestnet = "near_testnet" // needs underscore in rawValue
    case aptosTestnet = "aptos_testnet" // needs underscore in rawValue
    case suiTestnet = "sui_testnet" // needs underscore in rawValue
    case starknetGoerli = "starknet_goerli" // needs underscore in rawValue
    case tezosTestnet = "tezos_testnet" // needs underscore in rawValue
    case cosmosTestnet = "cosmos_testnet" // needs underscore in rawValue
    case polkadotTestnet = "polkadot_testnet" // needs underscore in rawValue
    case algorandTestnet = "algorand_testnet" // needs underscore in rawValue
    case osmosisTestnet = "osmosis_testnet" // needs underscore in rawValue
    case moneroTestnet = "monero_testnet" // needs underscore in rawValue
    case klaytnTestnet = "klaytn_testnet" // needs underscore in rawValue
    case vechainTestnet = "vechain_testnet" // needs underscore in rawValue
    case flowTestnet = "flow_testnet" // needs underscore in rawValue
    case immutableXTestnet = "immutable_x_testnet" // needs underscore in rawValue
    case roninTestnet = "ronin_testnet" // needs underscore in rawValue
    case oasisTestnet2 = "oasis_testnet" // needs underscore in rawValue, renamed to avoid conflict
    case internetComputerTestnet = "internet_computer_testnet" // needs underscore in rawValue
    case cardanoTestnet = "cardano_testnet" // needs underscore in rawValue
    case eosTestnet = "eos_testnet" // needs underscore in rawValue
    case thetaTestnet = "theta_testnet" // needs underscore in rawValue
    case hederaTestnet = "hedera_testnet" // needs underscore in rawValue
    case stacksTestnet = "stacks_testnet" // needs underscore in rawValue
    case ontologyTestnet = "ontology_testnet" // needs underscore in rawValue
    case waxTestnet = "wax_testnet" // needs underscore in rawValue
    case harmonyTestnet = "harmony_testnet" // needs underscore in rawValue
    case fuseTestnet = "fuse_testnet" // needs underscore in rawValue
    case cantoTestnet = "canto_testnet" // needs underscore in rawValue
    case auroraTestnet = "aurora_testnet" // needs underscore in rawValue
    case kavaTestnet = "kava_testnet" // needs underscore in rawValue
    case secretTestnet = "secret_testnet" // needs underscore in rawValue
    case moonriverTestnet = "moonriver_testnet" // needs underscore in rawValue
    case metisTestnet = "metis_testnet" // needs underscore in rawValue
    case telosTestnet = "telos_testnet" // needs underscore in rawValue
    case okcTestnet = "okc_testnet" // needs underscore in rawValue
    case confluxTestnet = "conflux_testnet" // needs underscore in rawValue
    case nervosTestnet = "nervos_testnet" // needs underscore in rawValue
    case iotexTestnet = "iotex_testnet" // needs underscore in rawValue
    case qtumTestnet = "qtum_testnet" // needs underscore in rawValue
    case syscoinTestnet = "syscoin_testnet" // needs underscore in rawValue
    case ultronTestnet = "ultron_testnet" // needs underscore in rawValue
    case elastosTestnet = "elastos_testnet" // needs underscore in rawValue
    case findoraTestnet = "findora_testnet" // needs underscore in rawValue
    case horizenTestnet = "horizen_testnet" // needs underscore in rawValue
    case oasisEmeraldTestnet = "oasis_emerald_testnet" // needs underscore in rawValue
    case tonTestnet = "ton_testnet" // needs underscore in rawValue
    case oasisSapphireTestnet = "oasis_sapphire_testnet" // needs underscore in rawValue
    case terraTestnet = "terra_testnet" // needs underscore in rawValue
    case terraClassicTestnet = "terra_classic_testnet" // needs underscore in rawValue


    var displayValue: String {
        switch self {
        case .ethereum: return "Ethereum"
        case .polygon: return "Polygon"
        case .arbitrum: return "Arbitrum"
        case .optimism: return "Optimism"
        case .bsc: return "Binance Smart Chain"
        case .avalanche: return "Avalanche"
        case .fantom: return "Fantom"
        case .gnosis: return "Gnosis Chain"
        case .celo: return "Celo"
        case .moonbeam: return "Moonbeam"
        case .cronos: return "Cronos"
        case .base: return "Base"
        case .zora: return "Zora"
        case .linea: return "Linea"
        case .scroll: return "Scroll"
        case .opBnb: return "opBNB"
        case .solana: return "Solana"
        case .bitcoin: return "Bitcoin"
        case .xrpl: return "XRP Ledger"
        case .litecoin: return "Litecoin"
        case .filecoin: return "Filecoin"
        case .near: return "Near"
        case .aptos: return "Aptos"
        case .sui: return "Sui"
        case .starknet: return "Starknet"
        case .tezos: return "Tezos"
        case .cosmos: return "Cosmos"
        case .polkadot: return "Polkadot"
        case .algorand: return "Algorand"
        case .osmosis: return "Osmosis"
        case .monero: return "Monero"
        case .klaytn: return "Klaytn"
        case .vechain: return "VeChain"
        case .flow: return "Flow"
        case .immutableX: return "ImmutableX"
        case .ronin: return "Ronin"
        case .oasis: return "Oasis"
        case .internetComputer: return "Internet Computer"
        case .cardano: return "Cardano"
        case .eos: return "EOS"
        case .theta: return "Theta"
        case .hedera: return "Hedera"
        case .stacks: return "Stacks"
        case .ontology: return "Ontology"
        case .wax: return "WAX"
        case .harmony: return "Harmony"
        case .fuse: return "Fuse"
        case .canto: return "Canto"
        case .aurora: return "Aurora"
        case .kava: return "Kava"
        case .secret: return "Secret"
        case .moonriver: return "Moonriver"
        case .metis: return "Metis"
        case .telos: return "Telos"
        case .okc: return "OKC"
        case .conflux: return "Conflux"
        case .nervos: return "Nervos"
        case .iotex: return "IoTeX"
        case .qtum: return "Qtum"
        case .syscoin: return "Syscoin"
        case .ultron: return "Ultron"
        case .elastos: return "Elastos"
        case .findora: return "Findora"
        case .horizen: return "Horizen"
        case .oasisEmerald: return "Oasis Emerald"
        case .ton: return "TON"
        case .oasisSapphire: return "Oasis Sapphire"
        case .terra: return "Terra"
        case .terraClassic: return "Terra Classic"

        // Testnets
        case .goerli: return "Goerli"
        case .sepolia: return "Sepolia"
        case .mumbai: return "Mumbai"
        case .arbitrumGoerli: return "Arbitrum Goerli"
        case .optimismGoerli: return "Optimism Goerli"
        case .bscTestnet: return "BSC Testnet"
        case .fuji: return "Fuji"
        case .fantomTestnet: return "Fantom Testnet"
        case .gnosisTestnet: return "Gnosis Testnet"
        case .alfajores: return "Alfajores"
        case .moonbaseAlpha: return "Moonbase Alpha"
        case .cronosTestnet: return "Cronos Testnet"
        case .baseGoerli: return "Base Goerli"
        case .zoraGoerli: return "Zora Goerli"
        case .lineaGoerli: return "Linea Goerli"
        case .scrollSepolia: return "Scroll Sepolia"
        case .opBnbTestnet: return "opBNB Testnet"
        case .solanaTestnet: return "Solana Testnet"
        case .bitcoinTestnet: return "Bitcoin Testnet"
        case .xrplTestnet: return "XRP Ledger Testnet"
        case .litecoinTestnet: return "Litecoin Testnet"
        case .filecoinTestnet: return "Filecoin Testnet"
        case .nearTestnet: return "Near Testnet"
        case .aptosTestnet: return "Aptos Testnet"
        case .suiTestnet: return "Sui Testnet"
        case .starknetGoerli: return "Starknet Goerli"
        case .tezosTestnet: return "Tezos Testnet"
        case .cosmosTestnet: return "Cosmos Testnet"
        case .polkadotTestnet: return "Polkadot Testnet"
        case .algorandTestnet: return "Algorand Testnet"
        case .osmosisTestnet: return "Osmosis Testnet"
        case .moneroTestnet: return "Monero Testnet"
        case .klaytnTestnet: return "Klaytn Testnet"
        case .vechainTestnet: return "VeChain Testnet"
        case .flowTestnet: return "Flow Testnet"
        case .immutableXTestnet: return "ImmutableX Testnet"
        case .roninTestnet: return "Ronin Testnet"
        case .oasisTestnet2: return "Oasis Testnet" // Renamed to avoid conflict
        case .internetComputerTestnet: return "Internet Computer Testnet"
        case .cardanoTestnet: return "Cardano Testnet"
        case .eosTestnet: return "EOS Testnet"
        case .thetaTestnet: return "Theta Testnet"
        case .hederaTestnet: return "Hedera Testnet"
        case .stacksTestnet: return "Stacks Testnet"
        case .ontologyTestnet: return "Ontology Testnet"
        case .waxTestnet: return "WAX Testnet"
        case .harmonyTestnet: return "Harmony Testnet"
        case .fuseTestnet: return "Fuse Testnet"
        case .cantoTestnet: return "Canto Testnet"
        case .auroraTestnet: return "Aurora Testnet"
        case .kavaTestnet: return "Kava Testnet"
        case .secretTestnet: return "Secret Testnet"
        case .moonriverTestnet: return "Moonriver Testnet"
        case .metisTestnet: return "Metis Testnet"
        case .telosTestnet: return "Telos Testnet"
        case .okcTestnet: return "OKC Testnet"
        case .confluxTestnet: return "Conflux Testnet"
        case .nervosTestnet: return "Nervos Testnet"
        case .iotexTestnet: return "IoTeX Testnet"
        case .qtumTestnet: return "Qtum Testnet"
        case .syscoinTestnet: return "Syscoin Testnet"
        case .ultronTestnet: return "Ultron Testnet"
        case .elastosTestnet: return "Elastos Testnet"
        case .findoraTestnet: return "Findora Testnet"
        case .horizenTestnet: return "Horizen Testnet"
        case .oasisEmeraldTestnet: return "Oasis Emerald Testnet"
        case .tonTestnet: return "TON Testnet"
        case .oasisSapphireTestnet: return "Oasis Sapphire Testnet"
        case .terraTestnet: return "Terra Testnet"
        case .terraClassicTestnet: return "Terra Classic Testnet"
        }
    }
}

extension Chain {
    /// An array containing all testnet chains defined in the `Chain` enum.
    ///
    /// This array is pre-computed for efficiency and should be updated whenever
    /// new testnet chains are added to the `Chain` enum.
    ///
    /// Source: https://docs.simplehash.com/reference/supported-chains-testnets
    static let testnets: [Chain] = [
        .goerli, .sepolia, .mumbai, .arbitrumGoerli, .optimismGoerli, .bscTestnet,
        .fuji, .fantomTestnet, .gnosisTestnet, .alfajores, .moonbaseAlpha, .cronosTestnet,
        .baseGoerli, .zoraGoerli, .lineaGoerli, .scrollSepolia, .opBnbTestnet, .solanaTestnet,
        .bitcoinTestnet, .xrplTestnet, .litecoinTestnet, .filecoinTestnet, .nearTestnet,
        .aptosTestnet, .suiTestnet, .starknetGoerli, .tezosTestnet, .cosmosTestnet,
        .polkadotTestnet, .algorandTestnet, .osmosisTestnet, .moneroTestnet, .klaytnTestnet,
        .vechainTestnet, .flowTestnet, .immutableXTestnet, .roninTestnet, .oasisTestnet2, // renamed in previous answer
        .internetComputerTestnet, .cardanoTestnet, .eosTestnet, .thetaTestnet, .hederaTestnet,
        .stacksTestnet, .ontologyTestnet, .waxTestnet, .harmonyTestnet, .fuseTestnet,
        .cantoTestnet, .auroraTestnet, .kavaTestnet, .secretTestnet, .moonriverTestnet,
        .metisTestnet, .telosTestnet, .okcTestnet, .confluxTestnet, .nervosTestnet,
        .iotexTestnet, .qtumTestnet, .syscoinTestnet, .ultronTestnet, .elastosTestnet,
        .findoraTestnet, .horizenTestnet, .oasisEmeraldTestnet, .tonTestnet, .oasisSapphireTestnet,
        .terraTestnet, .terraClassicTestnet
    ]

    /// An array containing all mainnet (non-testnet) chains defined in the `Chain` enum.
   ///
   /// This array is pre-computed for efficiency and should be updated whenever
   /// new mainnet chains are added to the `Chain` enum. Ensure that chains are correctly
   /// categorized as either mainnet or testnet when updating.
   ///
   /// Source: https://docs.simplehash.com/reference/supported-chains-testnets

    static let mainChains: [Chain] = [
        .ethereum, .polygon, .arbitrum, .optimism, .bsc, .avalanche, .fantom,
        .gnosis, .celo, .moonbeam, .cronos, .base, .zora, .linea, .scroll,
        .opBnb, .solana, .bitcoin, .xrpl, .litecoin, .filecoin, .near,
        .aptos, .sui, .starknet, .tezos, .cosmos, .polkadot, .algorand,
        .osmosis, .monero, .klaytn, .vechain, .flow, .immutableX, .ronin,
        .oasis, .internetComputer, .cardano, .eos, .theta, .hedera, .stacks,
        .ontology, .wax, .harmony, .fuse, .canto, .aurora, .kava, .secret,
        .moonriver, .metis, .telos, .okc, .conflux, .nervos, .iotex, .qtum,
        .syscoin, .ultron, .elastos, .findora, .horizen, .oasisEmerald, .ton,
        .oasisSapphire, .terra, .terraClassic
    ]

    static var unCatergarorized: [Chain] {
        Array(
            Set(allCases)
                .subtracting(Set(mainChains))
                .subtracting(Set(testnets))
        )
    }
}
