//
//  Secrets.swift
//  Auralis
//
//  Created by Daniel Bell on 3/22/25.
//

import Foundation

struct Secrets {
    enum APIKeyProvider: String {
        case moralis = "Moralis"
        case infura = "Infura"
    }
    static func apiKey(_ provider: APIKeyProvider) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let apiKey = dict["API_KEY"] as? [String:String] else {
            return nil
        }
        return apiKey[provider.rawValue]
    }
}
