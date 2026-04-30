import Foundation
import UIKit

@MainActor
protocol ApplicationURLChecking {
    func canOpenURL(_ url: URL) -> Bool
}

extension UIApplication: ApplicationURLChecking {}

enum ExternalWalletApp: String, CaseIterable {
    case metaMask = "metamask"
    case coinbaseWallet = "cbwallet"
    case rainbow
    case ledgerLive = "ledgerlive"

    var launchURL: URL {
        URL(string: "\(rawValue)://")!
    }
}

@MainActor
struct ExternalWalletAppProbe {
    private let application: any ApplicationURLChecking

    init(application: any ApplicationURLChecking = UIApplication.shared) {
        self.application = application
    }

    func canOpen(_ wallet: ExternalWalletApp) -> Bool {
        application.canOpenURL(wallet.launchURL)
    }
}
