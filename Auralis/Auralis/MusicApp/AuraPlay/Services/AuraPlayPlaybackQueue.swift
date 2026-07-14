import AuraPlayMediaCore
import Foundation

struct QueueEntry: Identifiable, Sendable {
    let id: UUID
    let item: AuraPlayableMediaItem

    init(id: UUID = UUID(), item: AuraPlayableMediaItem) {
        self.id = id
        self.item = item
    }
}

extension QueueEntry: Equatable {
    static func == (lhs: QueueEntry, rhs: QueueEntry) -> Bool {
        lhs.id == rhs.id && lhs.item.id == rhs.item.id
    }
}

enum QueueOrigin: Equatable, Sendable {
    case playlist(id: String)
    case collection(contractAddress: String)
    case search(query: String)
    case single(mediaItemID: String)
    case aiGenerated
    case restored
}

struct AuraPlayPlaybackQueue: Equatable, Sendable {
    private(set) var entries: [QueueEntry] = []
    private(set) var currentEntryID: UUID?
    private(set) var history: [QueueEntry] = []
    private(set) var origin: QueueOrigin = .aiGenerated

    var currentIndex: Int? {
        guard let currentEntryID else { return nil }
        return entries.firstIndex { $0.id == currentEntryID }
    }

    var currentEntry: QueueEntry? {
        currentIndex.map { entries[$0] }
    }

    var currentItem: AuraPlayableMediaItem? {
        currentEntry?.item
    }

    mutating func replaceQueue(
        with items: [AuraPlayableMediaItem],
        startAt index: Int,
        origin: QueueOrigin
    ) {
        entries = items.map { QueueEntry(item: $0) }
        currentEntryID = entries.indices.contains(index) ? entries[index].id : nil
        history.removeAll(keepingCapacity: true)
        self.origin = origin
    }

    @discardableResult
    mutating func insertNext(_ item: AuraPlayableMediaItem) -> QueueEntry {
        let entry = QueueEntry(item: item)
        guard let currentIndex else {
            entries.insert(entry, at: 0)
            currentEntryID = entry.id
            return entry
        }
        entries.insert(entry, at: min(entries.endIndex, currentIndex + 1))
        return entry
    }

    @discardableResult
    mutating func append(_ item: AuraPlayableMediaItem) -> QueueEntry {
        let entry = QueueEntry(item: item)
        entries.append(entry)
        if currentEntryID == nil {
            currentEntryID = entry.id
        }
        return entry
    }

    @discardableResult
    mutating func remove(entryID: UUID) -> Bool {
        guard entryID != currentEntryID,
              let index = entries.firstIndex(where: { $0.id == entryID }) else {
            return false
        }
        entries.remove(at: index)
        return true
    }

    @discardableResult
    mutating func reorder(entryID: UUID, toIndex: Int) -> Bool {
        guard let sourceIndex = entries.firstIndex(where: { $0.id == entryID }),
              entries.indices.contains(sourceIndex) else {
            return false
        }
        let entry = entries.remove(at: sourceIndex)
        let destination = min(max(0, toIndex), entries.count)
        entries.insert(entry, at: destination)
        return true
    }

    mutating func advance() -> QueueEntry? {
        guard let currentIndex else { return nil }
        let nextIndex = currentIndex + 1
        guard entries.indices.contains(nextIndex) else { return nil }
        pushHistory(entries[currentIndex])
        currentEntryID = entries[nextIndex].id
        return entries[nextIndex]
    }

    mutating func moveTo(entryID: UUID) -> QueueEntry? {
        guard let destinationIndex = entries.firstIndex(where: { $0.id == entryID }) else {
            return nil
        }
        if let currentIndex, currentEntryID != entryID {
            pushHistory(entries[currentIndex])
        }
        currentEntryID = entryID
        return entries[destinationIndex]
    }

    mutating func retreat() -> QueueEntry? {
        guard let currentIndex else { return nil }
        let previousIndex = currentIndex - 1
        guard entries.indices.contains(previousIndex) else { return nil }
        pushHistory(entries[currentIndex])
        currentEntryID = entries[previousIndex].id
        return entries[previousIndex]
    }

    func peekNext() -> QueueEntry? {
        guard let currentIndex else { return nil }
        let nextIndex = currentIndex + 1
        return entries.indices.contains(nextIndex) ? entries[nextIndex] : nil
    }

    mutating func restartFromBeginning() {
        currentEntryID = entries.first?.id
    }

    private mutating func pushHistory(_ entry: QueueEntry) {
        history.append(entry)
        if history.count > 50 {
            history.removeFirst(history.count - 50)
        }
    }
}

enum AuraPlayRepeatMode: String, CaseIterable, Codable, Equatable, Sendable {
    case off
    case one
    case all
}

enum AuraPlayShuffleMode: String, CaseIterable, Codable, Equatable, Sendable {
    case off
    case on
}

struct ShuffleCoordinator: Equatable, Sendable {
    private(set) var mode: AuraPlayShuffleMode = .off
    private(set) var shuffledOrder: [UUID] = []

    mutating func setMode(_ mode: AuraPlayShuffleMode, queue: AuraPlayPlaybackQueue) {
        self.mode = mode
        if mode == .on {
            rebuildOrder(queue: queue)
        } else {
            shuffledOrder.removeAll()
        }
    }

    mutating func rebuildOrder(queue: AuraPlayPlaybackQueue) {
        guard let currentEntryID = queue.currentEntryID else {
            shuffledOrder = queue.entries.map(\.id)
            return
        }
        let remaining = queue.entries.map(\.id).filter { $0 != currentEntryID }
        shuffledOrder = [currentEntryID] + remaining.shuffled()
    }

    func nextEntry(after entryID: UUID, queue: AuraPlayPlaybackQueue) -> QueueEntry? {
        guard mode == .on,
              let currentIndex = shuffledOrder.firstIndex(of: entryID) else {
            return queue.peekNext()
        }
        let nextIndex = currentIndex + 1
        guard shuffledOrder.indices.contains(nextIndex) else { return nil }
        let nextID = shuffledOrder[nextIndex]
        return queue.entries.first { $0.id == nextID }
    }
}
