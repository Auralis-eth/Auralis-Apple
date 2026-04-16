import CryptoKit
import Foundation

extension String {
    var seedBytes: [UInt8] {
        let hash = SHA256.hash(data: Data(utf8))
        return Array(hash)
    }

    func isValidEthAddress() -> Bool {
        let text = lowercased()
        guard text.hasPrefix("0x"), text.count == 42 else {
            return false
        }

        for character in text.dropFirst(2) {
            let isHex = ("0"..."9").contains(character) || ("a"..."f").contains(character)
            if !isHex {
                return false
            }
        }

        return true
    }
}
