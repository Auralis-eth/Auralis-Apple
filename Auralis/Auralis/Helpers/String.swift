//
//  String.swift
//  KickingHorse
//
//  Created by Daniel Bell on 8/24/24.
//

import Foundation

extension String {
    var isHexIgnorePrefix: Bool {
        guard !isEmpty else {
            return false
        }
        let updatedValue = hasPrefix("0x") ? self : "0x" + self
        return updatedValue.isHex
    }

    var isHex: Bool {
        range(of: #"^0x[0-9A-Fa-f]*$"#, options: .regularExpression) != nil
    }
}

extension String {
    func addressFormatedForDisplay() -> String {
        replacingOccurrences(of: dropFirst(6).dropLast(4), with: "...")
    }
}

extension String {
    var displayAddress: String {
        if count > 10 {
            let start = prefix(6)
            let end = suffix(4)
            return "\(start)...\(end)"
        }
        return self
    }
}
