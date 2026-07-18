import Foundation
import MusicFeature
#if canImport(UIKit)
import SafariServices
import UIKit
#endif

/// App-owned live implementations of the player/library context actions:
/// UIKit share sheet (with cached artwork image when available), in-app
/// Safari for explorer links, and pasteboard copy. `MusicFeature` only sees
/// the abstract `AuraPlayPlayerContextActionHandler`.
extension AuraPlayPlayerContextActionHandler {
    static var uiKitLive: AuraPlayPlayerContextActionHandler {
        AuraPlayPlayerContextActionHandler(
            share: { request in
                #if canImport(UIKit)
                guard let presenter = UIApplication.shared.auraPlayTopMostViewController else { return }
                var items: [Any] = [request.text]
                if let url = request.url {
                    items.append(url)
                }
                if let image = await cachedArtworkImage(for: request.artworkURLString) {
                    items.append(image)
                }
                let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
                presenter.present(controller, animated: true)
                #endif
            },
            open: { url in
                #if canImport(UIKit)
                guard let presenter = UIApplication.shared.auraPlayTopMostViewController else { return }
                let controller = SFSafariViewController(url: url)
                presenter.present(controller, animated: true)
                #endif
            },
            copy: { value in
                #if canImport(UIKit)
                UIPasteboard.general.string = value
                #endif
            }
        )
    }
}

#if canImport(UIKit)
/// Cache-only lookup so sharing never blocks on the network.
private func cachedArtworkImage(for urlString: String?) async -> UIImage? {
    guard let urlString, let url = URL(string: urlString) else { return nil }
    var request = URLRequest(url: url)
    request.cachePolicy = .returnCacheDataDontLoad
    guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
    return UIImage(data: data)
}

extension UIApplication {
    var auraPlayTopMostViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController?
            .auraPlayTopMostPresentedViewController
    }
}

private extension UIViewController {
    var auraPlayTopMostPresentedViewController: UIViewController {
        presentedViewController?.auraPlayTopMostPresentedViewController ?? self
    }
}
#endif
