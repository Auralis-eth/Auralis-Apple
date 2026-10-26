import AuraPlayMediaCore
import AuraUI
import SwiftUI

public struct AuraPlayPlayerGestureLayer<Commander: AuraPlayPlayerCommanding>: View {
    public let mediaKind: AuraPlayPlayerContentKind
    public let currentSeconds: TimeInterval
    public let durationSeconds: TimeInterval?
    public let commander: Commander
    public let accessibilityIdentifier: String
    @Binding public var isVideoChromeVisible: Bool
    public let dismiss: () -> Void

    /// Shared with the scrubber so drags and double-taps chase one target (P10-002).
    private let seekCoalescer: SeekCoalescer

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var feedback: SeekFeedback?

    public init(
        mediaKind: AuraPlayPlayerContentKind,
        currentSeconds: TimeInterval,
        durationSeconds: TimeInterval?,
        commander: Commander,
        accessibilityIdentifier: String,
        isVideoChromeVisible: Binding<Bool>,
        seekCoalescer: SeekCoalescer = SeekCoalescer(),
        dismiss: @escaping () -> Void
    ) {
        self.mediaKind = mediaKind
        self.currentSeconds = currentSeconds
        self.durationSeconds = durationSeconds
        self.commander = commander
        self.accessibilityIdentifier = accessibilityIdentifier
        self._isVideoChromeVisible = isVideoChromeVisible
        self.seekCoalescer = seekCoalescer
        self.dismiss = dismiss
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(doubleTapGesture(in: geometry.size))
                    .simultaneousGesture(middleTapGesture(in: geometry.size))
                    .simultaneousGesture(pinchGesture)
                    .simultaneousGesture(dismissGesture)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Player gestures")
                    .accessibilityHint("Use actions to skip by 10 seconds")
                    .accessibilityAction(named: "Skip Back 10 Seconds") {
                        requestSeek(delta: -10, direction: .backward)
                    }
                    .accessibilityAction(named: "Skip Forward 10 Seconds") {
                        requestSeek(delta: 10, direction: .forward)
                    }

                if let feedback {
                    SeekFeedbackView(feedback: feedback)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func doubleTapGesture(in size: CGSize) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                let third = size.width / 3
                if value.location.x <= third {
                    requestSeek(delta: -10, direction: .backward)
                } else if value.location.x >= third * 2 {
                    requestSeek(delta: 10, direction: .forward)
                }
            }
    }

    private func middleTapGesture(in size: CGSize) -> some Gesture {
        SpatialTapGesture(count: 1)
            .onEnded { value in
                guard mediaKind == .video else { return }
                let third = size.width / 3
                guard value.location.x > third, value.location.x < third * 2 else { return }
                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.2)) {
                    isVideoChromeVisible.toggle()
                }
            }
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onEnded { value in
                guard mediaKind == .video, abs(value - 1) > 0.08 else { return }
                Task { await commander.toggleVideoGravity() }
            }
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                guard value.translation.height > 90 || value.predictedEndTranslation.height > 160 else { return }
                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.82)) {
                    dismiss()
                }
            }
    }

    private func requestSeek(delta: TimeInterval, direction: SeekFeedback.Direction) {
        let duration = durationSeconds ?? .greatestFiniteMagnitude
        let target = min(duration, max(0, currentSeconds + delta))
        showFeedback(direction)
        Task {
            await seekCoalescer.requestSeek(to: target) { seconds, _ in
                await commander.seek(to: seconds)
            }
        }
    }

    private func showFeedback(_ direction: SeekFeedback.Direction) {
        let feedback = SeekFeedback(direction: direction)
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.78)) {
            self.feedback = feedback
        }
        Task {
            try? await Task.sleep(nanoseconds: reduceMotion ? 350_000_000 : 650_000_000)
            guard self.feedback?.id == feedback.id else { return }
            withAnimation(.easeOut(duration: 0.16)) {
                self.feedback = nil
            }
        }
    }
}

private struct SeekFeedback: Identifiable, Equatable {
    enum Direction {
        case backward
        case forward
    }

    let id = UUID()
    let direction: Direction
}

private struct SeekFeedbackView: View {
    let feedback: SeekFeedback

    var body: some View {
        Label(feedback.direction == .backward ? "-10" : "+10", systemImage: systemImage)
            .font(.headline.monospacedDigit())
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.black.opacity(0.62), in: Capsule())
            .foregroundStyle(.white)
    }

    private var systemImage: String {
        feedback.direction == .backward ? "gobackward.10" : "goforward.10"
    }
}
