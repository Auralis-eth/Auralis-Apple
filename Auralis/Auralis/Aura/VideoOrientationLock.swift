import AuraPlayVideoEngine
import SwiftUI

#if canImport(UIKit)
import UIKit

@MainActor
final class AuraVideoOrientationLock {
    static let shared = AuraVideoOrientationLock()

    private(set) var supportedOrientations: UIInterfaceOrientationMask = .portrait

    private init() {}

    func update(for presentationInfo: VideoPresentationInfo?) {
        let nextOrientations: UIInterfaceOrientationMask
        if let aspectRatio = presentationInfo?.aspectRatio, aspectRatio > 1.2 {
            nextOrientations = .allButUpsideDown
        } else {
            nextOrientations = .portrait
        }

        guard supportedOrientations != nextOrientations else { return }
        supportedOrientations = nextOrientations

        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .forEach { scene in
                scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: nextOrientations))
            }
    }
}

final class AuralisAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated {
            AuraVideoOrientationLock.shared.supportedOrientations
        }
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? {
        windows.first { $0.isKeyWindow }
    }
}
#endif
