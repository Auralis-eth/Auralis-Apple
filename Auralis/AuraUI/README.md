# AuraUI

AuraUI is the shared visual system for Auralis surfaces.

## Motion

Use `AuraMotionPolicy` for new SwiftUI animations in this package and in app features that import AuraUI. Build it from `@Environment(\.accessibilityReduceMotion)` and use `decorativeLoop` for ambient/infinite effects and `stateChange` for event-driven UI transitions.

Haptics currently remain conservative for 0.1.0: `AuraHaptics` is disabled when Reduce Motion is enabled. A dedicated haptics preference is deferred until product settings can expose that choice without adding another hidden control path.
