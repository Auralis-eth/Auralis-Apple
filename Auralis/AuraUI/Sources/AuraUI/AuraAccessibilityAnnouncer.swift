#if canImport(UIKit)
import UIKit
#endif

public enum AuraAccessibilityAnnouncer {
    public static func announce(_ message: String) {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }
}
