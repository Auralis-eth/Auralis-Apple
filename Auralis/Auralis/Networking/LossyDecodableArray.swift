import Foundation

struct LossyDecodableArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []

        while !container.isAtEnd {
            if let value = try? container.decode(Element.self) {
                elements.append(value)
            } else {
                _ = try? container.decode(IgnoredDecodableValue.self)
            }
        }

        self.elements = elements
    }
}

private struct IgnoredDecodableValue: Decodable {}
