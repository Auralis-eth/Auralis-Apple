import SwiftUI

@MainActor
public protocol AuraPlayPlayerVideoSurfacePresenting: AnyObject {
    var auraPlayPlayerVideoSurface: AnyView? { get }
    var auraPlayPlayerVideoRoutePicker: AnyView? { get }
}
