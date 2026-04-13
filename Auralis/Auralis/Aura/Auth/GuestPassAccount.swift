struct MetadataChunk: Identifiable, Hashable {
    var id: String {
        systemImage + text
    }

    let systemImage: String
    let text: String
}

enum AccountRole {
    case label
    case collector
    case artist

    var image: String {
        switch self {
        case .label:
            return "music.note.house.fill"
        case .collector:
            return Bool.random() ? "shippingbox.fill" : "headphones"
        case .artist:
            return Bool.random() ? "mic.fill" : "signature"
        }
    }
}

struct GuestPassAccount: Identifiable, Hashable {
    var id: String { address }
    let address: String
    let ens: String?
    let role: AccountRole
    let title: String
    let subtitle: String
    let metadata: [MetadataChunk]
}

extension GuestPassAccount {
    static let accounts: [GuestPassAccount] = [
        GuestPassAccount(
            address: "0x9266f125fb2ecb730d9953b46de9c32e2fa83e4a",
            ens: "cooprecords.eth",
            role: .label,
            title: "Coop Records",
            subtitle: "Modern on-chain label curating influential indie and electronic releases.",
            metadata: [
                MetadataChunk(systemImage: "music.note", text: "600+ releases; 150+ artists since Aug 2023"),
                MetadataChunk(systemImage: "link", text: "Active across 4+ chains; catalog primarily on Ethereum"),
                MetadataChunk(systemImage: "sparkles", text: "On-chain music launchpad with daily collectible drops")
            ]
        ),
        GuestPassAccount(
            address: "0x5b93ff82faaf241c15997ea3975419dddd8362c5",
            ens: "coopahtroopa.eth",
            role: .collector,
            title: "Coopahtroopa",
            subtitle: "Multi-chain music NFT super-collector and Coop Records founder wallet.",
            metadata: [
                MetadataChunk(systemImage: "globe", text: "Balances spread across ~14 chains on EVM L1/L2s"),
                MetadataChunk(systemImage: "music.mic", text: "Music NFT-heavy portfolio, including artist, label, and collector drops"),
                MetadataChunk(systemImage: "person.3.sequence", text: "Connected to Coop Records' on-chain label ecosystem")
            ]
        ),
        GuestPassAccount(
            address: "0xce90a7949bb78892f159f428d0dc23a8e3584d75",
            ens: "cozomomedici.eth",
            role: .collector,
            title: "Cozomo de' Medici",
            subtitle: "High-profile NFT collecting wallet associated with blue-chip and art NFTs.",
            metadata: [
                MetadataChunk(systemImage: "photo.on.rectangle", text: "Holds notable ERC-1155 and ERC-721 art and collectible NFTs"),
                MetadataChunk(systemImage: "link", text: "Long-running Ethereum collector address tracked on major explorers"),
                MetadataChunk(systemImage: "sparkles", text: "Frequently cited as a culturally influential NFT patron")
            ]
        ),
        GuestPassAccount(
            address: "0x38b6b4387Ff2776678E2B42f5EB2af4a452177d7",
            ens: "3lauvault.eth",
            role: .artist,
            title: "3LAU Vault",
            subtitle: "Vault wallet for 3LAU, early music NFT and royalty experiment pioneer (Royal founder).",
            metadata: [
                MetadataChunk(systemImage: "diamond.fill", text: "Holds curated NFT collection valued in the tens of ETH range"),
                MetadataChunk(systemImage: "music.note.list", text: "Includes music and art NFTs linked to 3LAU's on-chain releases"),
                MetadataChunk(systemImage: "link", text: "ENS relationships with 3lau.eth and other 3LAU identities")
            ]
        )
    ]
}
