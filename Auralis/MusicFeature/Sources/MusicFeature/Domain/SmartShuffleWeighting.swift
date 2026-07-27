import Foundation

public struct SmartShufflePlaybackHistory: Equatable, Sendable {
    public let mediaID: String
    public let lastPlayedAt: Date?
    public let playCount: Int

    public init(mediaID: String, lastPlayedAt: Date?, playCount: Int = 0) {
        self.mediaID = mediaID
        self.lastPlayedAt = lastPlayedAt
        self.playCount = max(0, playCount)
    }
}

public struct SmartShuffleWeightedItem<Item: Sendable>: Sendable {
    public let item: Item
    public let id: String
    public let weight: Double

    public init(item: Item, id: String, weight: Double) {
        self.item = item
        self.id = id
        self.weight = weight
    }
}

public enum SmartShuffleWeighting {
    public static func orderedItems<Item: Identifiable & Sendable>(
        _ items: [Item],
        history: [String: SmartShufflePlaybackHistory],
        now: Date,
        seed: UInt64 = 0
    ) -> [Item] where Item.ID == String {
        orderedItems(
            items,
            id: { $0.id },
            historyID: { $0.id },
            history: history,
            now: now,
            seed: seed
        )
    }

    public static func orderedItems<Item: Sendable>(
        _ items: [Item],
        id: (Item) -> String,
        historyID: (Item) -> String,
        history: [String: SmartShufflePlaybackHistory],
        now: Date,
        seed: UInt64 = 0
    ) -> [Item] {
        weightedItems(items, id: id, historyID: historyID, history: history, now: now)
            .sorted { lhs, rhs in
                let lhsKey = priorityKey(for: lhs, seed: seed)
                let rhsKey = priorityKey(for: rhs, seed: seed)
                if lhsKey == rhsKey {
                    return lhs.id < rhs.id
                }
                return lhsKey > rhsKey
            }
            .map(\.item)
    }

    public static func weightedItems<Item: Identifiable & Sendable>(
        _ items: [Item],
        history: [String: SmartShufflePlaybackHistory],
        now: Date
    ) -> [SmartShuffleWeightedItem<Item>] where Item.ID == String {
        weightedItems(items, id: { $0.id }, historyID: { $0.id }, history: history, now: now)
    }

    public static func weightedItems<Item: Sendable>(
        _ items: [Item],
        id: (Item) -> String,
        historyID: (Item) -> String,
        history: [String: SmartShufflePlaybackHistory],
        now: Date
    ) -> [SmartShuffleWeightedItem<Item>] {
        items.map { item in
            SmartShuffleWeightedItem(
                item: item,
                id: id(item),
                weight: weight(for: history[historyID(item)], now: now)
            )
        }
    }

    public static func weight(for history: SmartShufflePlaybackHistory?, now: Date) -> Double {
        guard let history else { return 1.0 }

        var weight = 1.0 / Double(history.playCount + 1)
        if let lastPlayedAt = history.lastPlayedAt {
            let age = max(0, now.timeIntervalSince(lastPlayedAt))
            if age < 24 * 60 * 60 {
                weight *= 0.15
            } else if age < 7 * 24 * 60 * 60 {
                weight *= 0.5
            }
        }
        return max(0.01, weight)
    }

    private static func priorityKey<Item: Sendable>(
        for weightedItem: SmartShuffleWeightedItem<Item>,
        seed: UInt64
    ) -> Double {
        let randomUnit = deterministicUnit(for: weightedItem.id, seed: seed)
        return pow(randomUnit, 1.0 / weightedItem.weight)
    }

    private static func deterministicUnit(for id: String, seed: UInt64) -> Double {
        var hash = seed == 0 ? 0xcbf29ce484222325 : seed
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        let bounded = hash % 1_000_000
        return max(0.000001, Double(bounded) / 1_000_000)
    }
}
