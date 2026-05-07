import AuralisPrimaryModels
import Foundation

extension ReceiptPayload {
    var timelineAccountAddress: String? {
        value(forKeys: ["accountAddress", "address"])?
            .extractedEthereumAddress?
            .lowercased()
    }

    var timelineChainRawValue: String? {
        guard let rawValue = value(forKeys: ["chain", "to_chain"]) else {
            return nil
        }

        return Chain(rawValue: rawValue)?.rawValue
    }

    var timelineSelectedChainRawValues: [String] {
        guard case .array(let values)? = values["selectedChains"] else {
            return []
        }

        return values.compactMap { value in
            guard case .string(let rawValue) = value else {
                return nil
            }

            return Chain(rawValue: rawValue)?.rawValue
        }
    }

    private func value(forKeys keys: [String]) -> String? {
        for key in keys {
            if case .string(let value)? = values[key] {
                return value
            }
        }

        return nil
    }
}
