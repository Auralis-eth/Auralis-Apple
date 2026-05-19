import Foundation

public enum EthereumAddressAccess: Codable, Sendable {
    case wallet
    case readonly

    public var canSign: Bool {
        switch self {
        case .wallet:
            return true
        case .readonly:
            return false
        }
    }
}

public enum EOAccountSource: String, Codable, Sendable {
    case manualEntry
    case qrScan
    case guestPass

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case Self.manualEntry.rawValue:
            self = .manualEntry
        case Self.qrScan.rawValue:
            self = .qrScan
        case Self.guestPass.rawValue:
            self = .guestPass
        default:
            self = .manualEntry
        }
    }
}
