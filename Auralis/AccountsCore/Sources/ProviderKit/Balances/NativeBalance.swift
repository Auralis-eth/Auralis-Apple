import Foundation

public struct NativeBalance: Equatable, Sendable {
    public let weiHex: String
    public let weiDecimal: String

    public init(weiHex: String, weiDecimal: String) {
        self.weiHex = weiHex
        self.weiDecimal = weiDecimal
    }

    public var formattedEtherDisplay: String {
        Self.formatEtherDisplay(fromWeiDecimal: weiDecimal)
    }

    public static func formatEtherDisplay(fromWeiDecimal weiDecimal: String) -> String {
        DecimalQuantityFormatter.formatEtherDisplay(fromWeiDecimal: weiDecimal)
    }
}
