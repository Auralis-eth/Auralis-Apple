import Foundation

extension String {
    public var extractedEthereumAddress: String? {
        let address = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else {
            return nil
        }

        let addressPattern = #"^0x[a-fA-F0-9]{40}$"#
        if let match = address.range(of: addressPattern, options: .regularExpression) {
            return String(address[match])
        }

        let noPrefixPattern = #"^[a-fA-F0-9]{40}$"#
        if let match = address.range(of: noPrefixPattern, options: .regularExpression) {
            return "0x" + String(address[match])
        }

        return nil
    }
}
