import AVFoundation
import SwiftUI

#if canImport(UIKit)
import UIKit

public final class PlayerSurfaceView: UIView {
    public override static var layerClass: AnyClass { AVPlayerLayer.self }

    public var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    public var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }
}

public struct PlayerContainerView: UIViewRepresentable {
    public let player: AVPlayer
    public let videoGravity: AVLayerVideoGravity

    /// Called from `makeUIView` and every SwiftUI update with the same backing layer.
    /// Hosts should keep PiP/controller creation idempotent for this layer.
    public let onLayerReady: (@MainActor (AVPlayerLayer) -> Void)?

    public init(
        player: AVPlayer,
        videoGravity: AVLayerVideoGravity = .resizeAspect,
        onLayerReady: (@MainActor (AVPlayerLayer) -> Void)? = nil
    ) {
        self.player = player
        self.videoGravity = videoGravity
        self.onLayerReady = onLayerReady
    }

    public func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.player = player
        view.playerLayer.videoGravity = videoGravity
        onLayerReady?(view.playerLayer)
        return view
    }

    public func updateUIView(_ uiView: PlayerSurfaceView, context: Context) {
        uiView.player = player
        uiView.playerLayer.videoGravity = videoGravity
        onLayerReady?(uiView.playerLayer)
    }

    public static func dismantleUIView(_ uiView: PlayerSurfaceView, coordinator: ()) {
        uiView.player = nil
    }
}
#elseif canImport(AppKit)
import AppKit

public final class PlayerSurfaceView: NSView {
    public let playerLayer = AVPlayerLayer()

    public var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer = playerLayer
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        layer = playerLayer
        wantsLayer = true
    }
}

public struct PlayerContainerView: NSViewRepresentable {
    public let player: AVPlayer
    public let videoGravity: AVLayerVideoGravity

    /// Called from `makeNSView` and every SwiftUI update with the same backing layer.
    /// Hosts should keep PiP/controller creation idempotent for this layer.
    public let onLayerReady: (@MainActor (AVPlayerLayer) -> Void)?

    public init(
        player: AVPlayer,
        videoGravity: AVLayerVideoGravity = .resizeAspect,
        onLayerReady: (@MainActor (AVPlayerLayer) -> Void)? = nil
    ) {
        self.player = player
        self.videoGravity = videoGravity
        self.onLayerReady = onLayerReady
    }

    public func makeNSView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.player = player
        view.playerLayer.videoGravity = videoGravity
        onLayerReady?(view.playerLayer)
        return view
    }

    public func updateNSView(_ nsView: PlayerSurfaceView, context: Context) {
        nsView.player = player
        nsView.playerLayer.videoGravity = videoGravity
        onLayerReady?(nsView.playerLayer)
    }

    public static func dismantleNSView(_ nsView: PlayerSurfaceView, coordinator: ()) {
        nsView.player = nil
    }
}
#endif
