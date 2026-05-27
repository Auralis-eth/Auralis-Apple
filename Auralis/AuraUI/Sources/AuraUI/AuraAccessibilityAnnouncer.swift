#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

@MainActor public enum AuraAccessibilityAnnouncer {
    public static func announce(_ message: String) {
        #if canImport(SwiftUI)
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) {
            AccessibilityNotification.Announcement(message).post()
            return
        }
        #endif

        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }

    public static func screenChanged(_ focusTarget: Any?) {
        #if canImport(SwiftUI)
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) {
            AccessibilityNotification.ScreenChanged(focusTarget).post()
            return
        }
        #endif

        #if canImport(UIKit)
        UIAccessibility.post(notification: .screenChanged, argument: focusTarget)
        #endif
    }

    public static func layoutChanged(_ focusTarget: Any?) {
        #if canImport(SwiftUI)
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) {
            AccessibilityNotification.LayoutChanged(focusTarget).post()
            return
        }
        #endif

        #if canImport(UIKit)
        UIAccessibility.post(notification: .layoutChanged, argument: focusTarget)
        #endif
    }
}
