import Foundation
import UIKit

@MainActor
extension NowPlayingService {
    func handleMemoryPressure() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastMemoryWarningTime > memoryWarningWindow { consecutiveMemoryWarnings = 0 }
        lastMemoryWarningTime = now
        consecutiveMemoryWarnings += 1

        let wallNow = Date()
        self.bucketRehydrateUntil = wallNow.addingTimeInterval(self.bucketRehydrateCooldown)

        if let control = currentArtworkControl {
            control.purge = true
            control.buckets = nil
            let paused = (lastPublishedRate ?? 1.0) == 0.0
            if (isBackgrounded || paused) && consecutiveMemoryWarnings >= 2 {
                self.ensurePlaceholderAvailable(on: control)
                control.dropMaster = true
            }
        }
        self.lastPlaceholderImage = nil
    }
}
