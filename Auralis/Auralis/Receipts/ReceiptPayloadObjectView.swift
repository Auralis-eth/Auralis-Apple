import SwiftUI

struct ReceiptPayloadObjectView: View {
    let values: [String: ReceiptJSONValue]
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(values.keys.sorted(), id: \.self) { key in
                if let value = values[key] {
                    ReceiptPayloadValueView(label: key, value: value, depth: depth)
                }
            }
        }
    }
}
