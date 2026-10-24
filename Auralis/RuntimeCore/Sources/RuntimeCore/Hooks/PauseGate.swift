/// The global kill switch, consulted by the governed pipeline before any tool call starts. (P1-204)
///
/// An actor so the off-main pipeline can read it safely while the UI toggles it. `RuntimeHost` mirrors
/// its observable `isPaused` into this gate.
public actor PauseGate {
    private var paused: Bool

    public init(paused: Bool = false) {
        self.paused = paused
    }

    public func setPaused(_ paused: Bool) {
        self.paused = paused
    }

    public func isPaused() -> Bool {
        paused
    }
}
