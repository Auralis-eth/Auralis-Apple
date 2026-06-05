import Foundation
import ObjectiveC
import Testing

public enum Fixture {
    public static let referenceDate = Date(timeIntervalSince1970: 1_704_067_200)

    public static func address(repeating character: Character) -> String {
        "0x" + String(repeating: String(character), count: 40)
    }
}

public extension Fixture {
    static func referenceDatePlus(seconds: TimeInterval) -> Date {
        referenceDate.addingTimeInterval(seconds)
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

public extension Tag {
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
