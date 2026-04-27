import Foundation

enum DecimalQuantityFormatter {
    struct TokenAmountPresentation: Equatable {
        let displayText: String
        let isHidden: Bool
    }

    static func tokenAmountPresentation(
        from rawBalance: String,
        decimals: Int?,
        symbol: String?
    ) -> TokenAmountPresentation {
        guard let decimals else {
            return TokenAmountPresentation(
                displayText: TokenHolding.hiddenAmountDisplay,
                isHidden: true
            )
        }

        let formattedAmount = formatDecimalQuantity(
            rawBalance,
            scale: max(decimals, 0),
            maxFractionDigits: 6
        )

        guard let symbol, !symbol.isEmpty else {
            return TokenAmountPresentation(
                displayText: formattedAmount,
                isHidden: false
            )
        }

        return TokenAmountPresentation(
            displayText: "\(formattedAmount) \(symbol)",
            isHidden: false
        )
    }

    static func formatEtherDisplay(fromWeiDecimal weiDecimal: String) -> String {
        let formattedAmount = formatDecimalQuantity(
            weiDecimal,
            scale: 18,
            maxFractionDigits: 6
        )
        return "\(formattedAmount) ETH"
    }

    private static func formatDecimalQuantity(
        _ rawValue: String,
        scale: Int,
        maxFractionDigits: Int
    ) -> String {
        let normalized = stripLeadingZeroes(from: rawValue)
        guard normalized != "0" else {
            return "0"
        }

        guard scale > 0 else {
            return normalized
        }

        let wholePart: String
        let fractionalPart: String

        if normalized.count <= scale {
            wholePart = "0"
            fractionalPart = String(repeating: "0", count: scale - normalized.count) + normalized
        } else {
            let splitIndex = normalized.index(normalized.endIndex, offsetBy: -scale)
            wholePart = String(normalized[..<splitIndex])
            fractionalPart = String(normalized[splitIndex...])
        }

        let visibleFraction = String(fractionalPart.prefix(maxFractionDigits))
        let trimmedFraction = visibleFraction.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
        if trimmedFraction.isEmpty {
            if wholePart == "0" && fractionalPart.contains(where: { $0 != "0" }) {
                return "<0." + String(repeating: "0", count: max(maxFractionDigits - 1, 0)) + "1"
            }
            return wholePart
        }

        return "\(wholePart).\(trimmedFraction)"
    }

    private static func stripLeadingZeroes(from value: String) -> String {
        let trimmed = value.drop { $0 == "0" }
        return trimmed.isEmpty ? "0" : String(trimmed)
    }
}
