import Foundation

struct DefaultReceiptPayloadSanitizer: ReceiptPayloadSanitizing {
    private let rpcURLKeys: Set<String> = [
        "rpcURL",
        "rpcUrl",
        "rpc_url",
        "rawRPCURL",
        "rawRpcURL",
        "raw_rpc_url"
    ]

    private let errorStringKeys: Set<String> = [
        "error",
        "errorMessage",
        "rawError",
        "raw_error"
    ]

    func sanitize(_ payload: RawReceiptPayload) -> ReceiptPayload {
        ReceiptPayload(values: sanitizeObject(payload.values))
    }
}

private extension DefaultReceiptPayloadSanitizer {
    func sanitizeObject(_ object: [String: ReceiptJSONValue]) -> [String: ReceiptJSONValue] {
        var sanitized: [String: ReceiptJSONValue] = [:]
        sanitized.reserveCapacity(object.count)

        for (key, value) in object {
            if rpcURLKeys.contains(key), case .string = value {
                sanitized[key] = .string("<redacted-rpc-url>")
                continue
            }

            if errorStringKeys.contains(key), case .string = value {
                sanitized[key] = .string("<redacted-error>")
                continue
            }

            sanitized[key] = sanitizeValue(value)
        }

        return sanitized
    }

    func sanitizeValue(_ value: ReceiptJSONValue) -> ReceiptJSONValue {
        switch value {
        case .object(let object):
            return .object(sanitizeObject(object))
        case .array(let values):
            return .array(values.map(sanitizeValue))
        default:
            return value
        }
    }
}
