import Foundation

@MainActor
final class AudioEngineProvider: ObservableObject {
    static let shared: AudioEngine = {
        do {
            return try AudioEngine()
        } catch {
            fatalError("Failed to initialize shared AudioEngine: \(error)")
        }
    }()
}
