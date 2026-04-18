import Foundation

@MainActor
class NFTExamples {
    static let musicNFT1 = NFT(
        id: "0x1234567890abcdef1234567890abcdef12345678:1",
        contract: NFT.Contract(address: "0x1234567890abcdef1234567890abcdef12345678"),
        tokenId: "1",
        tokenType: "ERC721",
        name: "Grimes - War Nymph",
        nftDescription: "A unique music NFT from Grimes' collection, featuring the song 'War Nymph' with exclusive digital artwork.",
        image: NFT.Image(
            originalUrl: "https://example.com/grimes/war_nymph.jpg",
            thumbnailUrl: "https://example.com/grimes/war_nymph_thumbnail.jpg"
        ),
        raw: nil,
        collection: NFT.Collection(name: "Grimes NFTs"),
        tokenUri: "https://example.com/grimes/war_nymph.json",
        timeLastUpdated: "2025-07-22T16:00:00Z",
        acquiredAt: NFT.AcquiredAt(blockTimestamp: "2025-07-20T10:30:00Z"),
        network: .ethMainnet,
        contentType: "audio/mp3",
        collectionName: "Grimes NFTs",
        artistName: "Grimes",
        audioUrl: "https://example.com/grimes/war_nymph.mp3"
    )
    static let musicNFT = NFT(
        id: "0x495f947276749ce646f68ac8c248420045cb7b5e:1",
        contract: NFT.Contract(address: "0x495f947276749ce646f68ac8c248420045cb7b5e"),
        tokenId: "1",
        tokenType: "ERC721",
        name: "Eternal Frequencies #001",
        nftDescription: "An experimental ambient composition exploring the intersection of generative music and blockchain technology. This piece evolves over 4 minutes and 32 seconds, featuring layered synthesizers and field recordings.",
        image: NFT.Image(
            originalUrl: "https://ipfs.io/ipfs/QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o",
            thumbnailUrl: "https://ipfs.io/ipfs/QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o/thumb.jpg"
        ),
        raw: NFT.Raw(
            tokenUri: "https://api.opensea.io/api/v1/metadata/0x495f947276749ce646f68ac8c248420045cb7b5e/1",
            metadata: [
                "name": .string("Eternal Frequencies #001"),
                "description": .string("An experimental ambient composition exploring the intersection of generative music and blockchain technology."),
                "image": .string("https://ipfs.io/ipfs/QmYjtig7VJQ6XsnUjqqJvj7QaMcCAwtrgNdahSiFofrE7o"),
                "animation_url": .string("https://ipfs.io/ipfs/QmPK1s3pNYLi9ERiq3BDxKa4XosgWwFRQUydHUtz4YgpqB/eternal_frequencies_001.mp3"),
                "attributes": .array([
                    .object([
                        "trait_type": .string("Genre"),
                        "value": .string("Ambient Electronic")
                    ]),
                    .object([
                        "trait_type": .string("Duration"),
                        "value": .string("4:32")
                    ]),
                    .object([
                        "trait_type": .string("BPM"),
                        "value": .string("72")
                    ]),
                    .object([
                        "trait_type": .string("Key"),
                        "value": .string("A Minor")
                    ]),
                    .object([
                        "trait_type": .string("Instruments"),
                        "value": .string("Modular Synthesizer, Field Recordings")
                    ])
                ])
            ]
        ),
        collection: NFT.Collection(name: "SoundWaves Collective"),
        tokenUri: "https://api.opensea.io/api/v1/metadata/0x495f947276749ce646f68ac8c248420045cb7b5e/1",
        timeLastUpdated: "2024-01-15T10:30:00.000Z",
        acquiredAt: NFT.AcquiredAt(blockTimestamp: "2024-01-15T10:30:00.000Z"),
        network: .ethMainnet,
        contentType: "audio/mpeg",
        collectionName: "SoundWaves Collective",
        artistName: "Luna Cipher",
        animationUrl: "https://ipfs.io/ipfs/QmPK1s3pNYLi9ERiq3BDxKa4XosgWwFRQUydHUtz4YgpqB/eternal_frequencies_001.mp3",
        audioUrl: "https://ipfs.io/ipfs/QmPK1s3pNYLi9ERiq3BDxKa4XosgWwFRQUydHUtz4YgpqB/eternal_frequencies_001.mp3"
    ).applying {
        $0.externalUrl = "https://lunaciphermusic.com"
        $0.artistWebsite = "https://lunaciphermusic.com"
        $0.medium = "Digital Audio"
        $0.sellerFeeBasisPoints = 750
        $0.aspectRatio = 1.0
    }

    static let pfpNFT = NFT(
        id: "0xbc4ca0eda7647a8ab7c2061c2e118a18a936f13d:5234",
        contract: NFT.Contract(address: "0xbc4ca0eda7647a8ab7c2061c2e118a18a936f13d"),
        tokenId: "5234",
        tokenType: "ERC721",
        name: "Bored Ape Yacht Club #5234",
        nftDescription: "A unique Bored Ape with rare traits. This ape is bored and ready for the metaverse!",
        image: NFT.Image(
            originalUrl: "https://ipfs.io/ipfs/QmRRPWG96cmgTn2qSzjwr2qvfNEuhunv6FNeMFGa9bx6mQ",
            thumbnailUrl: "https://ipfs.io/ipfs/QmRRPWG96cmgTn2qSzjwr2qvfNEuhunv6FNeMFGa9bx6mQ"
        ),
        raw: NFT.Raw(
            tokenUri: "https://ipfs.io/ipfs/QmeSjSinHpPnmXmspMjwiXyN6zS4E9zccariGR3jxcaWtq/5234",
            metadata: [
                "name": .string("Bored Ape Yacht Club #5234"),
                "description": .string("A unique Bored Ape with rare traits. This ape is bored and ready for the metaverse!"),
                "image": .string("https://ipfs.io/ipfs/QmRRPWG96cmgTn2qSzjwr2qvfNEuhunv6FNeMFGa9bx6mQ"),
                "attributes": .array([
                    .object([
                        "trait_type": .string("Background"),
                        "value": .string("Purple")
                    ]),
                    .object([
                        "trait_type": .string("Fur"),
                        "value": .string("Golden Brown")
                    ]),
                    .object([
                        "trait_type": .string("Eyes"),
                        "value": .string("Laser Eyes")
                    ]),
                    .object([
                        "trait_type": .string("Mouth"),
                        "value": .string("Bored Unshaven")
                    ]),
                    .object([
                        "trait_type": .string("Hat"),
                        "value": .string("Safari")
                    ]),
                    .object([
                        "trait_type": .string("Clothes"),
                        "value": .string("Leather Jacket")
                    ])
                ])
            ]
        ),
        collection: NFT.Collection(name: "Bored Ape Yacht Club"),
        tokenUri: "https://ipfs.io/ipfs/QmeSjSinHpPnmXmspMjwiXyN6zS4E9zccariGR3jxcaWtq/5234",
        timeLastUpdated: "2024-01-20T14:22:00.000Z",
        acquiredAt: NFT.AcquiredAt(blockTimestamp: "2021-04-30T12:15:00.000Z"),
        network: .ethMainnet,
        contentType: "image/png",
        collectionName: "Bored Ape Yacht Club",
        artistName: "Yuga Labs"
    ).applying {
        $0.externalUrl = "https://boredapeyachtclub.com"
        $0.backgroundColor = "purple"
        $0.sellerFeeBasisPoints = 250
        $0.aspectRatio = 1.0
    }

    static let generativeArt = NFT(
        id: "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270:23000456",
        contract: NFT.Contract(address: "0xa7d8d9ef8d8ce8992df33d8b8cf4aebabd5bd270"),
        tokenId: "23000456",
        tokenType: "ERC721",
        name: "Chromie Squiggle #456",
        nftDescription: "A simple, elegant, and unpredictable algorithm. Chromie Squiggles are the first 'Art Blocks Curated' project and the project that started the Art Blocks platform.",
        image: NFT.Image(
            originalUrl: "https://api.artblocks.io/image/23000456",
            thumbnailUrl: "https://api.artblocks.io/image/23000456"
        ),
        raw: NFT.Raw(
            tokenUri: "https://api.artblocks.io/token/23000456",
            metadata: [
                "name": .string("Chromie Squiggle #456"),
                "description": .string("A simple, elegant, and unpredictable algorithm."),
                "image": .string("https://api.artblocks.io/image/23000456"),
                "generator_url": .string("https://generator.artblocks.io/23000456"),
                "attributes": .array([
                    .object([
                        "trait_type": .string("Color Spread"),
                        "value": .string("High")
                    ]),
                    .object([
                        "trait_type": .string("Direction"),
                        "value": .string("Right and Up")
                    ]),
                    .object([
                        "trait_type": .string("Height"),
                        "value": .string("Normal")
                    ]),
                    .object([
                        "trait_type": .string("Pipe Count"),
                        "value": .string("5")
                    ]),
                    .object([
                        "trait_type": .string("Spectrum"),
                        "value": .string("Hyper")
                    ])
                ])
            ]
        ),
        collection: NFT.Collection(name: "Art Blocks Curated"),
        tokenUri: "https://api.artblocks.io/token/23000456",
        timeLastUpdated: "2024-01-18T09:45:00.000Z",
        acquiredAt: NFT.AcquiredAt(blockTimestamp: "2020-11-27T16:20:00.000Z"),
        network: .ethMainnet,
        contentType: "image/svg+xml",
        collectionName: "Chromie Squiggle",
        artistName: "Snowfro"
    ).applying {
        $0.externalUrl = "https://artblocks.io"
        $0.artistWebsite = "https://artblocks.io"
        $0.projectID = "0"
        $0.scriptType = "p5.js"
        $0.engineType = "Art Blocks Engine"
        $0.sellerFeeBasisPoints = 250
        $0.aspectRatio = 1.0
        $0.isStatic = 0
    }

    static let photographyNFT = NFT(
        id: "0x60f80121c31a0d46b5279700f9df786054aa5ee5:123456",
        contract: NFT.Contract(address: "0x60f80121c31a0d46b5279700f9df786054aa5ee5"),
        tokenId: "123456",
        tokenType: "ERC721",
        name: "Urban Solitude #17",
        nftDescription: "A contemplative street photography piece capturing the isolation and beauty found in urban environments during golden hour. Shot in downtown Tokyo, 2023.",
        image: NFT.Image(
            originalUrl: "https://ipfs.io/ipfs/QmNLei78zWmzUdbeRB3CiUfAizWUrbeeZh5K1rhAQKCh51",
            thumbnailUrl: "https://ipfs.io/ipfs/QmNLei78zWmzUdbeRB3CiUfAizWUrbeeZh5K1rhAQKCh51/thumb.jpg"
        ),
        raw: NFT.Raw(
            tokenUri: "https://raible.mypinata.cloud/ipfs/QmPtP2BNkUvGEuEPz7gBAw6qm96VxeqAjqQS6jgKG89V9M/123456.json",
            metadata: [
                "name": .string("Urban Solitude #17"),
                "description": .string("A contemplative street photography piece capturing the isolation and beauty found in urban environments."),
                "image": .string("https://ipfs.io/ipfs/QmNLei78zWmzUdbeRB3CiUfAizWUrbeeZh5K1rhAQKCh51"),
                "attributes": .array([
                    .object(["trait_type": .string("Location"), "value": .string("Tokyo, Japan")]),
                    .object(["trait_type": .string("Camera"), "value": .string("Leica Q2")]),
                    .object(["trait_type": .string("Lens"), "value": .string("28mm f/1.7")]),
                    .object(["trait_type": .string("ISO"), "value": .string("400")]),
                    .object(["trait_type": .string("Aperture"), "value": .string("f/2.8")]),
                    .object(["trait_type": .string("Year"), "value": .string("2023")])
                ])
            ]
        ),
        collection: NFT.Collection(name: "Foundation"),
        tokenUri: "https://raible.mypinata.cloud/ipfs/QmPtP2BNkUvGEuEPz7gBAw6qm96VxeqAjqQS6jgKG89V9M/123456.json",
        timeLastUpdated: "2024-01-12T11:15:00.000Z",
        acquiredAt: NFT.AcquiredAt(blockTimestamp: "2023-08-15T14:30:00.000Z"),
        network: .ethMainnet,
        contentType: "image/jpeg",
        collectionName: "Urban Chronicles",
        artistName: "Kenji Nakamura"
    ).applying {
        $0.externalUrl = "https://foundation.app"
        $0.artistWebsite = "https://kenjinakamura.photo"
        $0.medium = "Digital Photography"
        $0.sellerFeeBasisPoints = 1000
        $0.aspectRatio = 1.5
    }

    static let gamingNFT = NFT(
        id: "0x7bd29408f11d2bfc23c34f18275bbf23bb716bc7:15678",
        contract: NFT.Contract(address: "0x7bd29408f11d2bfc23c34f18275bbf23bb716bc7"),
        tokenId: "15678",
        tokenType: "ERC721",
        name: "CryptoVoxels Parcel #15678",
        nftDescription: "A prime real estate parcel in the heart of Origin City. This 16x16 plot includes building permissions and comes with exclusive neighborhood benefits.",
        image: NFT.Image(
            originalUrl: "https://www.cryptovoxels.com/parcels/15678.png",
            thumbnailUrl: "https://www.cryptovoxels.com/parcels/15678_thumb.png"
        ),
        raw: NFT.Raw(
            tokenUri: "https://www.cryptovoxels.com/p/15678",
            metadata: [
                "name": .string("CryptoVoxels Parcel #15678"),
                "description": .string("A prime real estate parcel in the heart of Origin City."),
                "image": .string("https://www.cryptovoxels.com/parcels/15678.png"),
                "external_url": .string("https://www.cryptovoxels.com/play?coords=N@15678"),
                "attributes": .array([
                    .object(["trait_type": .string("Area"), "value": .string("256")]),
                    .object(["trait_type": .string("Height"), "value": .string("20")]),
                    .object(["trait_type": .string("Suburb"), "value": .string("Origin City")]),
                    .object(["trait_type": .string("Island"), "value": .string("Origin")]),
                    .object(["trait_type": .string("Type"), "value": .string("parcel")]),
                    .object(["trait_type": .string("Elevation"), "value": .string("20")])
                ])
            ]
        ),
        collection: NFT.Collection(name: "CryptoVoxels"),
        tokenUri: "https://www.cryptovoxels.com/p/15678",
        timeLastUpdated: "2024-01-10T16:45:00.000Z",
        acquiredAt: NFT.AcquiredAt(blockTimestamp: "2022-03-12T10:20:00.000Z"),
        network: .ethMainnet,
        contentType: "application/json",
        collectionName: "CryptoVoxels",
        artistName: "Cryptovoxels Team"
    ).applying {
        $0.externalUrl = "https://www.cryptovoxels.com/play?coords=N@15678"
        $0.modelUrl = "https://www.cryptovoxels.com/parcels/15678.glb"
        $0.sellerFeeBasisPoints = 500
        $0.aspectRatio = 1.0
    }

    static let domainNFT = NFT(
        id: "0x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85:68789456",
        contract: NFT.Contract(address: "0x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85"),
        tokenId: "68789456789123456789012345678901234567890123456789012345678901",
        tokenType: "ERC721",
        name: "crypto.eth",
        nftDescription: "Ethereum Name Service domain name for crypto.eth - a premium Web3 domain name.",
        image: NFT.Image(
            originalUrl: "https://metadata.ens.domains/mainnet/0x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85/68789456789123456789012345678901234567890123456789012345678901/image",
            thumbnailUrl: "https://metadata.ens.domains/mainnet/0x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85/68789456789123456789012345678901234567890123456789012345678901/image"
        ),
        raw: NFT.Raw(
            tokenUri: "https://metadata.ens.domains/mainnet/0x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85/68789456789123456789012345678901234567890123456789012345678901",
            metadata: [
                "name": .string("crypto.eth"),
                "description": .string("crypto.eth, an ENS name."),
                "image": .string("https://metadata.ens.domains/mainnet/0x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85/68789456789123456789012345678901234567890123456789012345678901/image"),
                "attributes": .array([
                    .object(["trait_type": .string("Length"), "value": .string("6")]),
                    .object(["trait_type": .string("Segment Length"), "value": .string("6")]),
                    .object(["trait_type": .string("Character Set"), "value": .string("letter")]),
                    .object(["trait_type": .string("Registration Date"), "value": .string("2022-05-01")]),
                    .object(["trait_type": .string("Expiration Date"), "value": .string("2025-05-01")])
                ])
            ]
        ),
        collection: NFT.Collection(name: "ENS: Ethereum Name Service"),
        tokenUri: "https://metadata.ens.domains/mainnet/0x57f1887a8bf19b14fc0df6fd9b2acc9af147ea85/68789456789123456789012345678901234567890123456789012345678901",
        timeLastUpdated: "2024-01-15T08:20:00.000Z",
        acquiredAt: NFT.AcquiredAt(blockTimestamp: "2022-05-01T12:00:00.000Z"),
        network: .ethMainnet,
        contentType: "image/svg+xml",
        collectionName: "ENS: Ethereum Name Service",
        artistName: "ENS Team"
    ).applying {
        $0.externalUrl = "https://app.ens.domains/name/crypto.eth"
        $0.sellerFeeBasisPoints = 0
        $0.aspectRatio = 1.0
    }

    static let artNFT = NFT(
        id: "0xabcdef1234567890abcdef1234567890abcdef12:2",
        contract: NFT.Contract(address: "0xabcdef1234567890abcdef1234567890abcdef12"),
        tokenId: "2",
        tokenType: "ERC721",
        name: "DigitalDreamer - Nebula Voyage",
        nftDescription: "A stunning digital artwork by DigitalDreamer, depicting a journey through a vibrant nebula.",
        image: NFT.Image(
            originalUrl: "https://example.com/digitaldreamer/nebula_voyage.png",
            thumbnailUrl: "https://example.com/digitaldreamer/nebula_voyage_thumbnail.png"
        ),
        raw: nil,
        collection: NFT.Collection(name: "DigitalDreamer Collection"),
        tokenUri: "https://example.com/digitaldreamer/nebula_voyage.json",
        timeLastUpdated: "2025-07-22T15:00:00Z",
        acquiredAt: NFT.AcquiredAt(blockTimestamp: "2025-07-19T09:00:00Z"),
        network: .ethMainnet,
        contentType: "image/png",
        collectionName: "DigitalDreamer Collection",
        artistName: "DigitalDreamer"
    )

    static let collectibleNFT = NFT(
        id: "0xfedcba9876543210fedcba9876543210fedcba98:3",
        contract: NFT.Contract(address: "0xfedcba9876543210fedcba9876543210fedcba98"),
        tokenId: "3",
        tokenType: "ERC721",
        name: "CyberPets #3",
        nftDescription: "A unique digital pet from the CyberPets collection, with traits: color - blue, eyes - laser.",
        image: NFT.Image(
            originalUrl: "https://example.com/cyberpets/pet3.png",
            thumbnailUrl: "https://example.com/cyberpets/pet3_thumbnail.png"
        ),
        raw: nil,
        collection: NFT.Collection(name: "CyberPets"),
        tokenUri: "https://example.com/cyberpets/pet3.json",
        timeLastUpdated: "2025-07-22T14:00:00Z",
        acquiredAt: NFT.AcquiredAt(blockTimestamp: "2025-07-18T12:00:00Z"),
        network: .ethMainnet,
        contentType: "image/png",
        collectionName: "CyberPets",
        artistName: "CryptoCreators"
    )

    static let musicNFT2 = NFT(
        id: "0xABCDEF1234567890:001",
        contract: .init(address: "0xABCDEF1234567890"),
        tokenId: "001",
        tokenType: "ERC721",
        name: "Ethereal Tides",
        nftDescription: "A meditative ambient track blending analog synths with Ethereum transaction hash data.",
        image: .init(originalUrl: "https://example.com/images/ethereal-tides.png"),
        collection: .init(name: "Ambient on Chain"),
        tokenUri: "ipfs://QmMusic1234",
        network: .ethMainnet,
        contentType: "audio/mpeg",
        collectionName: "Ambient on Chain",
        artistName: "DJ Aurora",
        animationUrl: "https://example.com/visualizer/ethereal-tides",
        audioUrl: "https://example.com/audio/ethereal-tides.mp3"
    )

    static let artNFT2 = NFT(
        id: "0xART123456789:2048",
        contract: .init(address: "0xART123456789"),
        tokenId: "2048",
        tokenType: "ERC721",
        name: "Cyber Garden",
        nftDescription: "A surrealist depiction of a digital utopia, built from GAN-generated flora.",
        image: .init(originalUrl: "https://example.com/cyber-garden.jpg"),
        collection: .init(name: "Neon Eden"),
        tokenUri: "ipfs://QmVisual2048",
        network: .ethMainnet,
        contentType: "image/jpeg",
        collectionName: "Neon Eden",
        artistName: "Lumen Vox"
    )

    static let collectibleNFT2 = NFT(
        id: "0xPFP56789:4890",
        contract: .init(address: "0xPFP56789"),
        tokenId: "4890",
        tokenType: "ERC721",
        name: "Moonpunk #4890",
        nftDescription: "Moonpunk sporting a cyber jacket and laser eyes. Common traits.",
        image: .init(originalUrl: "https://moonpunks.io/images/4890.png"),
        collection: .init(name: "Moonpunks"),
        tokenUri: "ipfs://QmMoonPunk4890",
        network: .ethMainnet,
        contentType: "image/png",
        collectionName: "Moonpunks",
        artistName: "Moon Labs"
    )

    static let nft3DModel = NFT(
        id: "0x3DModelVault:77",
        contract: .init(address: "0x3DModelVault"),
        tokenId: "77",
        tokenType: "ERC721",
        name: "Voxel Sphinx",
        nftDescription: "An ancient guardian rebuilt as a voxel model, optimized for use in metaverse environments.",
        image: .init(originalUrl: "https://models.example.com/voxel-sphinx-thumb.png"),
        collection: .init(name: "Metaverse Relics"),
        tokenUri: "ipfs://QmVoxelSphinx77",
        network: .ethMainnet,
        contentType: "model/gltf-binary",
        collectionName: "Metaverse Relics",
        artistName: "VoxelMaster"
    )

    static let textPoetryNFT = NFT(
        id: "0xPoetryVault123:001",
        contract: .init(address: "0xPoetryVault123"),
        tokenId: "001",
        tokenType: "ERC721",
        name: "Solidity Sonnet #1",
        nftDescription: "A poetic ode to smart contracts written entirely in rhyming couplets.",
        image: .init(originalUrl: "https://nftpoems.io/cover1.png"),
        collection: .init(name: "Gaslight Verses"),
        tokenUri: "ipfs://QmPoemText001",
        network: .ethMainnet,
        contentType: "text/plain",
        collectionName: "Gaslight Verses",
        artistName: "Versebyte"
    )

    static let allExamples = [
        musicNFT,
        pfpNFT,
        generativeArt,
        photographyNFT,
        gamingNFT,
        domainNFT,
        artNFT,
        collectibleNFT,
        musicNFT2,
        collectibleNFT2,
        nft3DModel,
        textPoetryNFT
    ]
}

extension NFT {
    func applying(_ closure: (NFT) -> Void) -> NFT {
        closure(self)
        return self
    }
}
