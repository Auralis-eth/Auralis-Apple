import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import ObjectiveC
import ReceiptStorage
import Testing

public enum Fixture {
    public static let referenceDate = Date(timeIntervalSince1970: 1_704_067_200)

    public static func address(repeating character: Character) -> String {
        "0x" + String(repeating: String(character), count: 40)
    }

    public static func contract(_ suffix: String) -> String {
        let sanitized = suffix.lowercased().filter { $0.isHexDigit }
        let paddedSuffix = String(sanitized.suffix(40))
        return "0x" + String(repeating: "0", count: max(0, 40 - paddedSuffix.count)) + paddedSuffix
    }
}

public extension Fixture {
    static func referenceDatePlus(seconds: TimeInterval) -> Date {
        referenceDate.addingTimeInterval(seconds)
    }

    enum Accounts {
        public static let primary = Fixture.address(repeating: "1")
        public static let secondary = Fixture.address(repeating: "2")
        public static let tertiary = Fixture.address(repeating: "3")
    }

    enum Contracts {
        public static let `default` = "0x495f947276749ce646f68ac8c248420045cb7b5e"
        public static let alternate = Fixture.contract("8888888888888888888888888888888888888888")
    }

    static func tokenID(_ discriminator: String = "1") -> String {
        "fixture-token-\(discriminator)"
    }

    static func correlationID(_ discriminator: String = "1") -> String {
        "fixture-correlation-\(discriminator)"
    }
}

public extension Date {
    func plus(seconds: TimeInterval) -> Date {
        addingTimeInterval(seconds)
    }
}

public struct NFTFixture: @unchecked Sendable {
    public static let music = NFTFixture(
        tokenId: "music-1",
        contentType: "audio/mpeg",
        animationUrl: "https://example.com/music-1.mp3",
        audioUrl: "https://example.com/music-1.mp3"
    )
    public static let image = NFTFixture(
        tokenId: "image-1",
        contentType: "image/png",
        animationUrl: nil,
        audioUrl: nil,
        includeOwnedChildren: true
    )

    public var tokenId: String
    public var id: String?
    public var accountAddress: String
    public var contractAddress: String
    public var collectionName: String?
    public var network: Chain
    public var tokenType: String?
    public var name: String?
    public var nftDescription: String?
    public var imageOriginalUrl: String?
    public var imageThumbnailUrl: String?
    public var tokenURI: String?
    public var rawTokenURI: String?
    public var rawMetadata: [String: JSONValue]?
    public var timeLastUpdated: String?
    public var contentType: String?
    public var artistName: String?
    public var animationUrl: String?
    public var audioUrl: String?
    public var includeOwnedChildren: Bool

    public init(
        tokenId: String = "fixture-token",
        id: String? = nil,
        accountAddress: String = Fixture.Accounts.primary,
        contractAddress: String = Fixture.Contracts.default,
        collectionName: String? = "Fixture Collection",
        network: Chain = .ethMainnet,
        tokenType: String? = nil,
        name: String? = nil,
        nftDescription: String? = nil,
        imageOriginalUrl: String? = nil,
        imageThumbnailUrl: String? = nil,
        tokenURI: String? = nil,
        rawTokenURI: String? = nil,
        rawMetadata: [String: JSONValue]? = nil,
        timeLastUpdated: String? = "2025-01-01T00:00:00Z",
        contentType: String? = nil,
        artistName: String? = "Fixture Artist",
        animationUrl: String? = nil,
        audioUrl: String? = nil,
        includeOwnedChildren: Bool = false
    ) {
        self.tokenId = tokenId
        self.id = id
        self.accountAddress = accountAddress
        self.contractAddress = contractAddress
        self.collectionName = collectionName
        self.network = network
        self.tokenType = tokenType
        self.name = name
        self.nftDescription = nftDescription
        self.imageOriginalUrl = imageOriginalUrl
        self.imageThumbnailUrl = imageThumbnailUrl
        self.tokenURI = tokenURI
        self.rawTokenURI = rawTokenURI
        self.rawMetadata = rawMetadata
        self.timeLastUpdated = timeLastUpdated
        self.contentType = contentType
        self.artistName = artistName
        self.animationUrl = animationUrl
        self.audioUrl = audioUrl
        self.includeOwnedChildren = includeOwnedChildren
    }

    public func with(_ transform: (inout NFTFixture) -> Void) -> NFTFixture {
        var copy = self
        transform(&copy)
        return copy
    }

    public func build() -> NFT {
        let normalizedAccountAddress = NFT.normalizedScopeComponent(accountAddress) ?? "unscoped"
        let normalizedContractAddress = NFT.normalizedScopeComponent(contractAddress) ?? "unknown"
        let resolvedTokenURI = tokenURI ?? "ipfs://fixture-\(tokenId)"
        let resolvedImageOriginalUrl = imageOriginalUrl ?? "https://example.com/\(tokenId).png"
        let resolvedImageThumbnailUrl = imageThumbnailUrl ?? "https://example.com/\(tokenId)-thumb.png"
        let raw = rawTokenURI == nil && rawMetadata == nil && includeOwnedChildren == false
            ? nil
            : NFT.Raw(
                tokenUri: rawTokenURI ?? resolvedTokenURI,
                metadata: rawMetadata ?? ["title": .string("Fixture \(tokenId)")]
            )

        return NFT(
            id: id ?? "\(normalizedAccountAddress):\(network.rawValue):\(normalizedContractAddress):\(tokenId)",
            contract: NFT.Contract(address: contractAddress, chain: network),
            tokenId: tokenId,
            tokenType: tokenType,
            name: name ?? "Fixture \(tokenId)",
            nftDescription: nftDescription,
            image: includeOwnedChildren || imageOriginalUrl != nil || imageThumbnailUrl != nil ? {
                let image = NFT.Image(
                    originalUrl: resolvedImageOriginalUrl,
                    thumbnailUrl: resolvedImageThumbnailUrl
                )
                image.secureUrl = resolvedImageOriginalUrl
                return image
            }() : nil,
            raw: raw,
            collection: collectionName.map {
                NFT.Collection(
                    name: $0,
                    chain: network,
                    contractAddress: contractAddress
                )
            },
            tokenUri: resolvedTokenURI,
            timeLastUpdated: timeLastUpdated,
            acquiredAt: includeOwnedChildren ? NFT.AcquiredAt(blockTimestamp: "2025-01-01T00:00:00Z") : nil,
            network: network,
            accountAddress: accountAddress,
            contentType: contentType,
            collectionName: collectionName,
            artistName: artistName,
            animationUrl: animationUrl,
            audioUrl: audioUrl
        )
    }
}

public struct MusicLibraryItemFixture: @unchecked Sendable {
    public static let music = MusicLibraryItemFixture()

    public var id: String
    public var sourceNFTID: String
    public var accountAddress: String
    public var network: Chain
    public var title: String
    public var artistName: String?
    public var collectionName: String?
    public var artworkURLString: String?
    public var contentType: String?
    public var playbackURLString: String?
    public var availability: MusicLibraryAvailability
    public var availabilityReason: String?
    public var sourceUpdatedAtRawValue: String?
    public var indexedAt: Date

    public init(
        id: String = "fixture-track",
        sourceNFTID: String = "fixture-source-nft",
        accountAddress: String = Fixture.Accounts.primary,
        network: Chain = .ethMainnet,
        title: String = "Fixture Track",
        artistName: String? = "Fixture Artist",
        collectionName: String? = "Fixture Collection",
        artworkURLString: String? = nil,
        contentType: String? = "audio/mpeg",
        playbackURLString: String? = "https://example.com/fixture-track.mp3",
        availability: MusicLibraryAvailability = .ready,
        availabilityReason: String? = nil,
        sourceUpdatedAtRawValue: String? = nil,
        indexedAt: Date = Fixture.referenceDate
    ) {
        self.id = id
        self.sourceNFTID = sourceNFTID
        self.accountAddress = accountAddress
        self.network = network
        self.title = title
        self.artistName = artistName
        self.collectionName = collectionName
        self.artworkURLString = artworkURLString
        self.contentType = contentType
        self.playbackURLString = playbackURLString
        self.availability = availability
        self.availabilityReason = availabilityReason
        self.sourceUpdatedAtRawValue = sourceUpdatedAtRawValue
        self.indexedAt = indexedAt
    }

    public func with(_ transform: (inout MusicLibraryItemFixture) -> Void) -> MusicLibraryItemFixture {
        var copy = self
        transform(&copy)
        return copy
    }

    public func build() -> MusicLibraryItem {
        MusicLibraryItem(
            id: id,
            sourceNFTID: sourceNFTID,
            accountAddressRawValue: accountAddress,
            networkRawValue: network.rawValue,
            title: title,
            artistName: artistName,
            collectionName: collectionName,
            normalizedTitleKey: title.lowercased(),
            normalizedArtistKey: artistName?.lowercased() ?? "",
            normalizedCollectionKey: collectionName?.lowercased() ?? "",
            artworkURLString: artworkURLString ?? "https://example.com/\(id).png",
            contentType: contentType,
            playbackURLString: playbackURLString,
            availability: availability,
            availabilityReason: availabilityReason,
            sourceUpdatedAtRawValue: sourceUpdatedAtRawValue,
            indexedAt: indexedAt
        )
    }
}

public struct StoredReceiptFixture: @unchecked Sendable {
    public static var successful: StoredReceiptFixture { StoredReceiptFixture() }

    public var id: UUID
    public var sequenceID: Int
    public var createdAt: Date
    public var actor: ReceiptActor
    public var mode: ReceiptMode
    public var trigger: String
    public var scope: String
    public var summary: String
    public var provenance: String
    public var isSuccess: Bool
    public var correlationID: String?
    public var accountAddress: String?
    public var chainRawValue: String?
    public var accountSequenceID: Int
    public var payloadHash: String
    public var previousReceiptHash: String
    public var chainHash: String
    public var details: ReceiptPayload

    public init(
        id: UUID = UUID(),
        sequenceID: Int = 1,
        createdAt: Date = Fixture.referenceDate,
        actor: ReceiptActor = .system,
        mode: ReceiptMode = .observe,
        trigger: String = "fixture.trigger",
        scope: String = "fixture.scope",
        summary: String = "fixture.summary",
        provenance: String = "tests",
        isSuccess: Bool = true,
        correlationID: String? = nil,
        accountAddress: String? = Fixture.Accounts.primary,
        chainRawValue: String? = Chain.ethMainnet.rawValue,
        accountSequenceID: Int = 1,
        payloadHash: String = "fixture-payload-hash",
        previousReceiptHash: String = "fixture-previous-hash",
        chainHash: String = "fixture-chain-hash",
        details: ReceiptPayload = ReceiptPayload(values: [:])
    ) {
        self.id = id
        self.sequenceID = sequenceID
        self.createdAt = createdAt
        self.actor = actor
        self.mode = mode
        self.trigger = trigger
        self.scope = scope
        self.summary = summary
        self.provenance = provenance
        self.isSuccess = isSuccess
        self.correlationID = correlationID
        self.accountAddress = accountAddress
        self.chainRawValue = chainRawValue
        self.accountSequenceID = accountSequenceID
        self.payloadHash = payloadHash
        self.previousReceiptHash = previousReceiptHash
        self.chainHash = chainHash
        self.details = details
    }

    public func with(_ transform: (inout StoredReceiptFixture) -> Void) -> StoredReceiptFixture {
        var copy = self
        transform(&copy)
        return copy
    }

    public func build() throws -> StoredReceipt {
        try StoredReceipt(
            id: id,
            sequenceID: sequenceID,
            createdAt: createdAt,
            actor: actor,
            mode: mode,
            trigger: trigger,
            scope: scope,
            summary: summary,
            provenance: provenance,
            isSuccess: isSuccess,
            correlationID: correlationID,
            timelineAccountAddress: accountAddress,
            timelineChainRawValue: chainRawValue,
            accountSequenceID: accountSequenceID,
            payloadHash: payloadHash,
            previousReceiptHash: previousReceiptHash,
            chainHash: chainHash,
            details: details
        )
    }
}

public struct UserDefaultsBox: @unchecked Sendable {
    public let defaults: UserDefaults

    public init(_ defaults: UserDefaults) {
        self.defaults = defaults
    }
}

public enum TestSupport {
    public static func temporaryUserDefaults(
        prefix: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> (defaults: UserDefaults, cleanup: () -> Void) {
        let suiteName = "\(prefix).\(UUID().uuidString)"
        let defaults = try #require(
            UserDefaults(suiteName: suiteName),
            sourceLocation: sourceLocation
        )
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, { defaults.removePersistentDomain(forName: suiteName) })
    }
}

public extension Testing.Tag {
    @Tag static var smoke: Self
    @Tag static var slow: Self
    @Tag static var networking: Self
    @Tag static var swiftdata: Self
    @Tag static var architecture: Self
    @Tag static var privacy: Self
}

public class URLProtocolMock: URLProtocol {
    public typealias Handler = @Sendable (URLRequest) throws -> (URLResponse, Data)

    nonisolated(unsafe) private static let handlerKey = UnsafeRawPointer(bitPattern: 0x4175_7261_6c69_7354)!

    private final class HandlerBox: NSObject {
        let handler: Handler

        init(handler: @escaping Handler) {
            self.handler = handler
        }
    }

    static func makeProtocolClass(handler: @escaping Handler) -> AnyClass {
        let className = "AuralisTestSupport.URLProtocolMock.\(UUID().uuidString)"
        guard let subclass = objc_allocateClassPair(URLProtocolMock.self, className, 0) else {
            return URLProtocolMock.self
        }

        objc_setAssociatedObject(
            subclass,
            handlerKey,
            HandlerBox(handler: handler),
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        objc_registerClassPair(subclass)
        return subclass
    }

    private class func handler(for protocolClass: AnyClass) -> Handler? {
        (objc_getAssociatedObject(protocolClass, handlerKey) as? HandlerBox)?.handler
    }

    public override class func canInit(with request: URLRequest) -> Bool {
        handler(for: self) != nil
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        guard let handler = Self.handler(for: object_getClass(self)!) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    public override func stopLoading() {}
}

public extension URLSession {
    static func mocked(_ handler: @escaping URLProtocolMock.Handler) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolMock.makeProtocolClass(handler: handler)]
        return URLSession(configuration: configuration)
    }
}
