import SwiftUI

struct ReceiptPayloadValueView: View {
    let label: String
    let value: ReceiptJSONValue
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch value {
            case .object(let object):
                ReceiptPayloadNestedHeader(label: label, depth: depth, kind: "Object")
                ReceiptPayloadObjectView(values: object, depth: depth + 1)
                    .padding(.leading, 12)
            case .array(let values):
                ReceiptPayloadNestedHeader(label: label, depth: depth, kind: "Array")
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        ReceiptPayloadValueView(
                            label: "[\(index)]",
                            value: value,
                            depth: depth + 1
                        )
                    }
                }
                .padding(.leading, 12)
            default:
                HStack(alignment: .top, spacing: 12) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 120, alignment: .leading)

                    Text(formattedScalar(value))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                        .textSelection(.enabled)

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func formattedScalar(_ value: ReceiptJSONValue) -> String {
        switch value {
        case .string(let string):
            return string
        case .number(let number):
            return number.formatted()
        case .bool(let bool):
            return bool ? "true" : "false"
        case .null:
            return "null"
        case .object, .array:
            return ""
        }
    }
}
