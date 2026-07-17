import GoogleSignInSwift
import SwiftUI

/// The iOS Account Control in its disconnected presentation.
///
/// The control uses Google's supplied SwiftUI sign-in button so branding,
/// localization, and the disabled presentation stay Google-owned. The wide
/// labeled form appears only when it fits the width the iOS Calendar Header
/// offers; the icon form is used whenever the width is constrained. Both
/// forms provide at least a 44-point activation target and announce their
/// Connect action to VoiceOver.
///
/// This slice is presentational: the Connect flow arrives with the
/// connection module, so `connect` defaults to a no-op.
struct IOSAccountControl: View {
    /// Whether Connect is available. Missing or invalid build configuration
    /// disables the control through Google's supplied disabled state.
    let connectEnabled: Bool

    /// The requested Connect action. The connection module wires this up;
    /// the shell defaults it to a no-op.
    let connect: () -> Void

    init(connectEnabled: Bool, connect: @escaping () -> Void = {}) {
        self.connectEnabled = connectEnabled
        self.connect = connect
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            googleButton(style: .wide)
                .fixedSize()
            googleButton(style: .icon)
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel("Connect Google account")
    }

    private func googleButton(style: GoogleSignInButtonStyle) -> some View {
        GoogleSignInButton(
            scheme: .light,
            style: style,
            state: connectEnabled ? .normal : .disabled,
            action: connect
        )
    }
}
