import SwiftUI

public struct AuraMotionPolicy {
    private let reduceMotion: Bool

    public init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
    }

    public var decorativeLoop: Animation? {
        reduceMotion ? nil : .linear(duration: 4).repeatForever(autoreverses: false)
    }

    public var stateChange: Animation? {
        reduceMotion ? nil : .snappy
    }
}
