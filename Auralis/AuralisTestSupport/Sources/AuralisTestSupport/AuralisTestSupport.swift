import AuralisFoundation
import AuralisPrimaryModels
import AuralisPrimaryPersistence
import Foundation
import ObjectiveC
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

public struct UserDefaultsBox: @unchecked Sendable {
    public let defaults: UserDefaults

    public init(_ defaults: UserDefaults) {
        self.defaults = defaults
    }
}

/// A mutex-guarded box for capturing a value out of an escaping, off-main-thread callback.
///
/// Exists for the ``URLSession/mocked(_:)`` handler, which `URLProtocol` invokes on a background
/// thread: a test that wants to assert *what was requested* has to write from there and read from
/// the test body, and a plain `var` capture is a data race Swift 6 rejects outright.
///
/// `ChainProvidersTests` already used this type, and it did not exist — so that suite never compiled,
/// which went unnoticed because ChainProviders has no CI lane and no Xcode test-plan entry. The build
/// failure was the first thing a lane for it would have reported.
public final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    public init(_ value: Value) {
        storedValue = value
    }

    public var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    public func set(_ newValue: Value) {
        lock.lock()
        defer { lock.unlock() }
        storedValue = newValue
    }

    /// Reads and writes under one acquisition, for callers that need read-modify-write to be atomic.
    @discardableResult
    public func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&storedValue)
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
