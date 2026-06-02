import AgentIdentityCore
import Testing

@Suite
struct AgentIdentityCoreTests {
    @Test("package marker type is available to downstream modules")
    func packageMarkerTypeIsAvailable() {
        #expect(String(describing: AgentIdentityCore.self) == "AgentIdentityCore")
    }
}
