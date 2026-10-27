import Foundation

public struct RuntimeContextTouch: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public let kind: AgentSessionMemoryTouchKind
    public let key: String
    public let dataClass: ContextDataClass?
    public let recordedAt: Date

    public init(
        id: UUID = UUID(),
        kind: AgentSessionMemoryTouchKind,
        key: String,
        dataClass: ContextDataClass? = nil,
        recordedAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.key = key
        self.dataClass = dataClass
        self.recordedAt = recordedAt
    }

    public var sessionMemoryTouch: AgentSessionMemoryTouch {
        AgentSessionMemoryTouch(
            id: id,
            kind: kind,
            key: key,
            dataClass: dataClass,
            recordedAt: recordedAt
        )
    }
}

public protocol RuntimeContextRecording: Sendable {
    func recordContextRefresh(key: String, dataClass: ContextDataClass?, correlationID: String) async
    func recordMemoryTouch(kind: AgentSessionMemoryTouchKind, key: String, dataClass: ContextDataClass?, correlationID: String) async
    func touches(correlationID: String) async -> [RuntimeContextTouch]
    func resetAll() async
}

public extension RuntimeContextRecording {
    func recordContextRefresh(key: String, dataClass: ContextDataClass? = nil, correlationID: String) async {
        await recordContextRefresh(key: key, dataClass: dataClass, correlationID: correlationID)
    }

    func recordMemoryTouch(
        kind: AgentSessionMemoryTouchKind,
        key: String,
        dataClass: ContextDataClass? = nil,
        correlationID: String
    ) async {
        await recordMemoryTouch(kind: kind, key: key, dataClass: dataClass, correlationID: correlationID)
    }
}

public actor RuntimeContextRecorder: RuntimeContextRecording {
    private var touchesByCorrelationID: [String: [RuntimeContextTouch]] = [:]

    public init() { }

    public func recordContextRefresh(key: String, dataClass: ContextDataClass?, correlationID: String) {
        record(RuntimeContextTouch(kind: .contextRefresh, key: key, dataClass: dataClass), correlationID: correlationID)
    }

    public func recordMemoryTouch(
        kind: AgentSessionMemoryTouchKind,
        key: String,
        dataClass: ContextDataClass?,
        correlationID: String
    ) {
        record(RuntimeContextTouch(kind: kind, key: key, dataClass: dataClass), correlationID: correlationID)
    }

    public func touches(correlationID: String) -> [RuntimeContextTouch] {
        touchesByCorrelationID[correlationID] ?? []
    }

    public func resetAll() {
        touchesByCorrelationID.removeAll()
    }

    private func record(_ touch: RuntimeContextTouch, correlationID: String) {
        touchesByCorrelationID[correlationID, default: []].append(touch)
    }
}
