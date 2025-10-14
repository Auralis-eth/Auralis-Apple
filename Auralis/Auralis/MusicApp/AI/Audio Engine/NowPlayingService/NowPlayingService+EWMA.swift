import Foundation

@MainActor
extension NowPlayingService {
    struct HostEWMAEntry: Codable { let host: String; let ewma: Double; let lastSeen: Date }

    func persistEWMA(now: Date = Date()) {
        var entries: [HostEWMAEntry] = []
        for (host, value) in hostLatencyEWMA {
            if let ts = hostLastSeen[host], now.timeIntervalSince(ts) <= ewmaInactivityTTL {
                entries.append(HostEWMAEntry(host: host, ewma: value, lastSeen: ts))
            }
        }
        entries.sort { $0.lastSeen > $1.lastSeen }
        if entries.count > ewmaMaxHosts { entries = Array(entries.prefix(ewmaMaxHosts)) }
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: ewmaPersistKey)
        } catch {
        }
    }

    func restoreEWMA(now: Date = Date()) {
        guard let data = UserDefaults.standard.data(forKey: ewmaPersistKey) else { return }
        do {
            let entries = try JSONDecoder().decode([HostEWMAEntry].self, from: data)
            var restored: [String: TimeInterval] = [:]
            var seen: [String: Date] = [:]
            for e in entries {
                if now.timeIntervalSince(e.lastSeen) <= ewmaInactivityTTL {
                    restored[e.host] = min(max(e.ewma, minFirstAttemptCellularTimeout), maxFirstAttemptCellularTimeout)
                    seen[e.host] = e.lastSeen
                }
            }
            let sorted = seen.sorted { $0.value > $1.value }
            let limited = sorted.prefix(ewmaMaxHosts)
            self.hostLatencyEWMA = Dictionary(uniqueKeysWithValues: limited.map { ($0.key, restored[$0.key] ?? cellularFastTimeout) })
            self.hostLastSeen = Dictionary(uniqueKeysWithValues: limited.map { ($0.key, $0.value) })
        } catch {
        }
    }

    func pruneEWMAIfNeeded(now: Date = Date()) {
        if !hostLastSeen.isEmpty {
            for (h, ts) in hostLastSeen {
                if now.timeIntervalSince(ts) > ewmaInactivityTTL {
                    hostLastSeen.removeValue(forKey: h)
                    hostLatencyEWMA.removeValue(forKey: h)
                }
            }
        }
        if hostLastSeen.count > ewmaMaxHosts {
            let over = hostLastSeen.count - ewmaMaxHosts
            let sorted = hostLastSeen.sorted { $0.value < $1.value }
            for i in 0..<min(over, sorted.count) {
                let h = sorted[i].key
                hostLastSeen.removeValue(forKey: h)
                hostLatencyEWMA.removeValue(forKey: h)
            }
        }
    }

    func ewmaEstimate(for host: String) -> TimeInterval {
        let now = Date()
        if let ts = hostLastSeen[host], now.timeIntervalSince(ts) <= ewmaInactivityTTL, let v = hostLatencyEWMA[host] {
            return v
        }
        return cellularFastTimeout
    }

    func updateEWMA(for host: String, sample seconds: TimeInterval) {
        guard !host.isEmpty, seconds.isFinite, seconds > 0 else { return }
        let now = Date()
        pruneEWMAIfNeeded(now: now)
        let prev = hostLatencyEWMA[host] ?? cellularFastTimeout
        let next = (ewmaAlpha * seconds) + ((1.0 - ewmaAlpha) * prev)
        hostLatencyEWMA[host] = min(max(next, minFirstAttemptCellularTimeout), maxFirstAttemptCellularTimeout)
        hostLastSeen[host] = now
        if hostLastSeen.count > ewmaMaxHosts {
            pruneEWMAIfNeeded(now: now)
        }
    }
}
