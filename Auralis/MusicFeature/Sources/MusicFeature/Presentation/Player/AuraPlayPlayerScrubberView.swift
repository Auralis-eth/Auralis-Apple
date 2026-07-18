import AuraPlayMediaCore
import AuraUI
import SwiftUI

private enum AuraPlayPlayerScrubberDefaults {
    static let trailingTimePreferenceKey = "com.auraplay.player.showsRemainingTime"
}

public struct AuraPlayPlayerScrubberView<Commander: AuraPlayPlayerCommanding>: View {
    public let position: AuraPlayPlayerPositionPresentation
    public let commander: Commander
    /// Shared with the gesture layer so drags and double-taps chase one target (P10-002).
    private let seekCoalescer: SeekCoalescer

    @State private var dragValue: Double?
    @AppStorage(AuraPlayPlayerScrubberDefaults.trailingTimePreferenceKey) private var showsRemainingTime = true

    private var duration: Double {
        max(1, position.durationSeconds ?? 1)
    }

    private var displayedValue: Double {
        min(duration, max(0, dragValue ?? position.currentSeconds))
    }

    public init(
        position: AuraPlayPlayerPositionPresentation,
        commander: Commander,
        seekCoalescer: SeekCoalescer = SeekCoalescer()
    ) {
        self.position = position
        self.commander = commander
        self.seekCoalescer = seekCoalescer
    }

    public var body: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { displayedValue },
                    set: { dragValue = $0 }
                ),
                in: 0...duration,
                onEditingChanged: handleEditingChanged
            )
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(elapsedText) of \(durationText)")
            .accessibilityAdjustableAction(adjust)
            .accessibilityIdentifier(A11yID.AuraPlay.playerScrubber)

            HStack {
                Text(elapsedText)
                    .monospacedDigit()
                    .accessibilityIdentifier(A11yID.AuraPlay.playerElapsedTime)
                Spacer()
                Button(showsRemainingTime ? remainingText : durationText) {
                    showsRemainingTime.toggle()
                }
                .buttonStyle(.plain)
                .monospacedDigit()
                .accessibilityLabel(showsRemainingTime ? "Remaining time" : "Total duration")
                .accessibilityIdentifier(A11yID.AuraPlay.playerTrailingTime)
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.72))
        }
        .opacity(position.isBuffering ? 0.82 : 1)
        .tint(.blue)
    }

    private var elapsedText: String {
        AuraPlayPlayerTimeFormatter.string(from: displayedValue)
    }

    private var durationText: String {
        AuraPlayPlayerTimeFormatter.string(from: position.durationSeconds)
    }

    private var remainingText: String {
        "-\(AuraPlayPlayerTimeFormatter.string(from: max(0, duration - displayedValue)))"
    }

    private func handleEditingChanged(_ isEditing: Bool) {
        guard !isEditing else { return }
        let target = displayedValue
        dragValue = nil
        Task {
            await seekCoalescer.requestSeek(to: target) { seconds, _ in
                await commander.seek(to: seconds)
            }
        }
    }

    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        let delta: Double
        switch direction {
        case .increment:
            delta = 10
        case .decrement:
            delta = -10
        @unknown default:
            return
        }
        let target = min(duration, max(0, displayedValue + delta))
        dragValue = target
        Task {
            await seekCoalescer.requestSeek(to: target) { seconds, _ in
                await commander.seek(to: seconds)
            }
        }
    }
}
