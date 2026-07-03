import AVFoundation
import Foundation

#if canImport(AVKit) && canImport(UIKit)
import AVKit

@MainActor
public final class PictureInPictureController: NSObject, @preconcurrency AVPictureInPictureControllerDelegate {
    public private(set) var state: PiPState = .inactive
    public var onStateChanged: ((PiPState) -> Void)?
    public var onRestoreRequested: (() -> Bool)?

    private let logger: VideoEngineLogging
    private var controller: AVPictureInPictureController?

    public init(playerLayer: AVPlayerLayer, logger: VideoEngineLogging = NoOpVideoEngineLogger()) {
        self.logger = logger
        super.init()

        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            state = .unsupported
            logger.info("Picture in Picture is not supported on this device.")
            return
        }

        controller = AVPictureInPictureController(playerLayer: playerLayer)
        controller?.delegate = self
        controller?.canStartPictureInPictureAutomaticallyFromInline = true
    }

    public func start() {
        guard let controller else {
            updateState(.unsupported)
            return
        }

        guard controller.isPictureInPicturePossible else {
            logger.info("Picture in Picture is not possible in the current context.")
            return
        }

        updateState(.starting)
        controller.startPictureInPicture()
    }

    public func stop() {
        guard let controller else { return }
        updateState(.stopping)
        controller.stopPictureInPicture()
    }

    public func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        handleDidStartPictureInPicture()
    }

    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        handleDidStopPictureInPicture()
    }

    public func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(handleRestoreUserInterfaceForPictureInPictureStop())
    }

    func handleDidStartPictureInPicture() {
        updateState(.active)
    }

    func handleDidStopPictureInPicture() {
        updateState(.inactive)
    }

    func handleRestoreUserInterfaceForPictureInPictureStop() -> Bool {
        onRestoreRequested?() ?? false
    }

    private func updateState(_ newState: PiPState) {
        guard state != newState else { return }
        state = newState
        onStateChanged?(newState)
    }
}
#else
@MainActor
public final class PictureInPictureController {
    public private(set) var state: PiPState = .unsupported
    public var onStateChanged: ((PiPState) -> Void)?
    public var onRestoreRequested: (() -> Bool)?

    public init(playerLayer: AVPlayerLayer, logger: VideoEngineLogging = NoOpVideoEngineLogger()) {}
    public func start() { onStateChanged?(.unsupported) }
    public func stop() {}
}
#endif
