import Testing
@testable import Planner

@Suite("Connection Dot Appearance")
struct ConnectionDotAppearanceTests {
    @Test("A connected control presents a steady green dot")
    func connected() {
        let presentation = GoogleAccountConnection.ControlPresentation
            .connected(
                GoogleAccountConnection.GoogleConnectedProfile(
                    displayName: "Ada Planner",
                    imageURL: nil
                )
            )
        #expect(ConnectionDotAppearance(presentation) == .connected)
    }

    @Test("A disconnected control presents a steady gray dot")
    func disconnected() {
        // Whether Connect is enabled or not, the settled disconnected
        // presentation is the same steady gray dot.
        #expect(
            ConnectionDotAppearance(.disconnected(connectEnabled: true))
                == .disconnected
        )
        #expect(
            ConnectionDotAppearance(.disconnected(connectEnabled: false))
                == .disconnected
        )
    }

    @Test("Restoring and connecting present a pulsing gray dot")
    func inFlight() {
        #expect(ConnectionDotAppearance(.restoring) == .inFlight)
        #expect(ConnectionDotAppearance(.connecting) == .inFlight)
    }

    @Test("Warnings and errors can never change the dot")
    func warningsAndErrorsCannotReachTheDot() {
        // The mapping reads only the control presentation; the connection
        // module's status — where expired, offline, failed, and cancelled
        // live — is not an input. An established connection survives an
        // offline period with a warning, and its dot stays connected-green.
        let presentation = GoogleAccountConnection.ControlPresentation
            .connected(
                GoogleAccountConnection.GoogleConnectedProfile(
                    displayName: nil,
                    imageURL: nil
                )
            )
        #expect(ConnectionDotAppearance(presentation) == .connected)
    }
}
