import SwiftUI

#if canImport(AVKit) && canImport(UIKit) && !os(visionOS)
import AVKit
import UIKit

public struct VideoRoutePickerView: UIViewRepresentable {
    public init() {}

    public func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        Self.configure(picker)
        return picker
    }

    public func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        Self.configure(uiView)
    }

    static func configure(_ picker: AVRoutePickerView) {
        picker.prioritizesVideoDevices = true
    }
}
#else
public struct VideoRoutePickerView: View {
    public init() {}

    public var body: some View {
        EmptyView()
    }
}
#endif
