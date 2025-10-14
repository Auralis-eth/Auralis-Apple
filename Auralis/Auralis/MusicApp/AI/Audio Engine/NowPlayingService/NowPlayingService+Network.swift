import Foundation
import Network

@MainActor
extension NowPlayingService {
    func startPathMonitorIfNeeded() {
        var shouldStart = false
        pathMonitorQueue.sync {
            if !self.pathMonitorActiveFlag {
                self.pathMonitorActiveFlag = true
                shouldStart = true
            }
        }
        if shouldStart {
            let monitor = NWPathMonitor()
            self.pathMonitor = monitor

            self.isCellular = true
            self.hasPathUpdate = false

            monitor.pathUpdateHandler = { [weak self] path in
                let onCell = path.isExpensive
                Task { @MainActor [weak self] in
                    self?.isCellular = onCell
                    self?.hasPathUpdate = true
                }
            }
            monitor.start(queue: pathMonitorQueue)
            pathMonitorStarted = true
        }
        schedulePathMonitorStop()
    }

    func schedulePathMonitorStop() {
        pathMonitorQueue.async { [weak self] in
            guard let self = self else { return }
            if let t = self.pathMonitorIdleTimer {
                t.cancel()
                self.pathMonitorIdleTimer = nil
            }
            let timer = DispatchSource.makeTimerSource(queue: self.pathMonitorQueue)
            timer.schedule(deadline: .now() + self.pathMonitorIdleGrace, repeating: DispatchTimeInterval.never)
            timer.setEventHandler { [weak self] in
                guard let self = self else { return }
                self.pathMonitorActiveFlag = false
                if let monitor = self.pathMonitor {
                    monitor.cancel()
                    self.pathMonitor = nil
                }
                if let t2 = self.pathMonitorIdleTimer { t2.cancel() }
                self.pathMonitorIdleTimer = nil
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.pathMonitorStarted = false
                    self.hasPathUpdate = false
                }
            }
            self.pathMonitorIdleTimer = timer
            timer.resume()
        }
    }
}
