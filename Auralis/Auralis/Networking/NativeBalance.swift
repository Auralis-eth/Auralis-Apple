import Foundation

struct NativeBalance: Equatable, Sendable {
    let weiHex: String
    let weiDecimal: String

    var formattedEtherDisplay: String {
        Self.formatEtherDisplay(fromWeiDecimal: weiDecimal)
    }

    static func formatEtherDisplay(fromWeiDecimal weiDecimal: String) -> String {
        DecimalQuantityFormatter.formatEtherDisplay(fromWeiDecimal: weiDecimal)
    }
}
