import SwiftUI

public class SVGFont {

    public let name: String
    public let size: CGFloat
    public let weight: String

    public init(name: String = "Serif", size: CGFloat = 16, weight: String = "normal") {
        self.name = name
        self.size = size
        self.weight = weight
    }

    public func toSwiftUI() -> Font {
        return Font.custom(name, size: size)//.weight(fontWeight)
    }
}


