import SwiftUI
import AVKit

struct AVRoutePicker: UIViewRepresentable {
    var tintColor: UIColor?

    init(tintColor: UIColor? = nil) {
        self.tintColor = tintColor
    }

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        if let tintColor { view.tintColor = tintColor }
        view.prioritizesVideoDevices = false // music only
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        if let tintColor { uiView.tintColor = tintColor }
    }
}

#Preview {
    AVRoutePicker()
        .frame(width: 44, height: 44)
        .padding()
}
