import SwiftUI
import Combine

public class SVGShape: SVGNode {

    @Published public var fill: SVGPaint?
    @Published public var stroke: SVGStroke?
}
