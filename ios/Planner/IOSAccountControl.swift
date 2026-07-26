import SwiftUI

/// The iOS Account Control across its connection presentations.
///
/// The disconnected presentation is a Planner-styled capsule mirroring the
/// connected form: a person-glyph circle in place of the avatar, a
/// "Connect Google" label only when the measured width fits, and an
/// enter-style affordance glyph. While restoration or a connection attempt
/// is in flight, the same capsule renders dimmed and non-interactive, so
/// there is no false Connect and no repeated activation. Planner owns the
/// copy (English-only); no Google logo or "Sign in with Google" phrasing
/// appears, per the custom-connect-control ADR.
///
/// The connected presentation is a Planner-styled capsule with the account
/// avatar — profile image when it loads, initials otherwise — a Disconnect
/// on This Device affordance, and the display name only when the measured
/// width fits it. One activation disconnects immediately, without
/// confirmation.
///
/// Every form provides at least a 44-point activation target, keeps focus,
/// pointer, and hover behavior native, and announces its action and the
/// connected account identity to VoiceOver.
///
/// Every form also carries the connection dot: a badge floating just past
/// the capsule's top-trailing corner that presents the Google Account
/// Connection state at a glance — green when connected, gray when
/// disconnected, pulsing gray while restoring or connecting. The dot is an
/// overlay, so it adds no width to the trailing control cluster; it is
/// decorative for VoiceOver because the control already announces the
/// connection state; and its trailing alignment mirrors naturally for
/// right-to-left. Connection warnings and errors never change the dot —
/// the iOS Header Status text carries them.
struct IOSAccountControl: View {
    /// The connection module's current control presentation.
    let presentation: GoogleAccountConnection.ControlPresentation

    /// The requested Connect action.
    let connect: () -> Void

    /// The requested Disconnect on This Device action.
    let disconnectOnThisDevice: () -> Void

    init(
        presentation: GoogleAccountConnection.ControlPresentation,
        connect: @escaping () -> Void = {},
        disconnectOnThisDevice: @escaping () -> Void = {}
    ) {
        self.presentation = presentation
        self.connect = connect
        self.disconnectOnThisDevice = disconnectOnThisDevice
    }

    var body: some View {
        let dot = ConnectionDotAppearance(presentation)
        switch presentation {
        case .disconnected(let connectEnabled):
            DisconnectedAccountControl(
                connectEnabled: connectEnabled,
                dotAppearance: dot,
                connect: connect
            )
        case .restoring, .connecting:
            // Restoration and interactive Connect both present the dimmed,
            // non-interactive capsule: no false Connect, no repeated
            // activation.
            DisconnectedAccountControl(
                connectEnabled: false,
                dotAppearance: dot,
                connect: connect
            )
        case .connected(let profile):
            ConnectedAccountControl(
                profile: profile,
                dotAppearance: dot,
                disconnectOnThisDevice: disconnectOnThisDevice
            )
        }
    }
}

/// The connection dot's appearance, resolved purely from the connection
/// module's control presentation and separated for deterministic tests, in
/// the style of the header's pure layout and status-resolution seams.
///
/// The mapping reads the control presentation only: connection warnings
/// and errors live on the module's status, never reach this seam, and so
/// can never change the dot.
enum ConnectionDotAppearance: Equatable, Sendable {
    /// Connected: a steady green dot.
    case connected

    /// Disconnected: a steady gray dot.
    case disconnected

    /// Restoring or connecting: a pulsing gray dot.
    case inFlight

    init(_ presentation: GoogleAccountConnection.ControlPresentation) {
        switch presentation {
        case .connected:
            self = .connected
        case .disconnected:
            self = .disconnected
        case .restoring, .connecting:
            self = .inFlight
        }
    }
}

/// The connection dot badge: a small filled circle overlaid on the account
/// capsule's top-trailing corner, nudged eight points outward past the edge.
/// As an overlay it contributes nothing to the capsule's measured
/// footprint, so the trailing control cluster's width budget, the Visible
/// Month's centering, and every neighboring control's position are
/// unaffected. The in-flight form pulses; the settled forms are steady.
/// The dot is hidden from VoiceOver — the control's own label and hint
/// already carry the connection state.
private struct ConnectionDotBadge: View {
    let appearance: ConnectionDotAppearance

    /// The outward nudge mirrors with the capsule: eight points past the
    /// trailing edge in either layout direction.
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        badge
            .offset(
                x: layoutDirection == .rightToLeft ? -8 : 8,
                y: -3
            )
    }

    @ViewBuilder
    private var badge: some View {
        if appearance == .inFlight {
            dot
                .phaseAnimator([1.0, 0.3]) { content, phase in
                    content.opacity(phase)
                } animation: { _ in
                    .easeInOut(duration: 0.9)
                }
        } else {
            dot
        }
    }

    private var dot: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch appearance {
        case .connected:
            return PlannerPalette.connectionDotConnected
        case .disconnected, .inFlight:
            return PlannerPalette.connectionDotDisconnected
        }
    }
}

/// The disconnected form: the mirror of the connected capsule — a
/// person-glyph circle in place of the avatar, the "Connect Google" label
/// only when the measured width fits (the compact form takes over before
/// the capsule could crowd the centered Visible Month), and an enter-style
/// affordance glyph distinct from the connected form's disconnect glyph.
/// While disabled, the capsule is non-interactive and dimmed.
private struct DisconnectedAccountControl: View {
    let connectEnabled: Bool
    let dotAppearance: ConnectionDotAppearance
    let connect: () -> Void

    @FocusState private var focused: Bool
    @State private var hovered = false

    var body: some View {
        Button(action: connect) {
            ViewThatFits(in: .horizontal) {
                disconnectedContent(showLabel: true)
                    .fixedSize()
                disconnectedContent(showLabel: false)
            }
        }
        .buttonStyle(
            AccountCapsuleButtonStyle(emphasized: focused || hovered)
        )
        .focused($focused)
        .onHover { hovered = $0 }
        .disabled(!connectEnabled)
        .opacity(connectEnabled ? 1 : 0.6)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .hoverEffect()
        // The label leads with the visible button text so VoiceOver and
        // Voice Control match what sighted users see; the hint names
        // Planner's action.
        .accessibilityLabel("Connect Google")
        .accessibilityHint("Connects your Google account")
    }

    private func disconnectedContent(showLabel: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(PlannerPalette.emphasizedControl)

                Image(systemName: "person.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PlannerPalette.olive)
            }
            .frame(width: 28, height: 28)

            if showLabel {
                Text("Connect Google")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PlannerPalette.ink)
                    .lineLimit(1)
            }

            Image(systemName: "arrow.right.to.line.compact")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PlannerPalette.olive)
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .frame(height: 36)
        .overlay(alignment: .topTrailing) {
            ConnectionDotBadge(appearance: dotAppearance)
        }
    }
}

/// The connected form: the account avatar and the Disconnect on This
/// Device affordance in a Planner-styled capsule, with the display name
/// only when the measured width fits it — the compact form takes over
/// before the capsule could crowd the centered Visible Month. One
/// activation disconnects immediately; there is no confirmation step.
private struct ConnectedAccountControl: View {
    let profile: GoogleAccountConnection.GoogleConnectedProfile
    let dotAppearance: ConnectionDotAppearance
    let disconnectOnThisDevice: () -> Void

    @FocusState private var focused: Bool
    @State private var hovered = false

    var body: some View {
        Button(action: disconnectOnThisDevice) {
            ViewThatFits(in: .horizontal) {
                connectedContent(showDisplayName: true)
                    .fixedSize()
                connectedContent(showDisplayName: false)
            }
        }
        .buttonStyle(
            AccountCapsuleButtonStyle(emphasized: focused || hovered)
        )
        .focused($focused)
        .onHover { hovered = $0 }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .hoverEffect()
        .accessibilityLabel(accessibilityName)
        .accessibilityHint("Disconnects on this device")
    }

    private func connectedContent(showDisplayName: Bool) -> some View {
        HStack(spacing: 6) {
            ConnectedAccountAvatar(profile: profile)
                .frame(width: 28, height: 28)

            if showDisplayName,
               let displayName = profile.displayName,
               !displayName.isEmpty
            {
                Text(displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(PlannerPalette.ink)
                    .lineLimit(1)
            }

            Image(systemName: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PlannerPalette.ink)
        }
        .padding(.leading, 4)
        .padding(.trailing, 10)
        .frame(height: 36)
        .overlay(alignment: .topTrailing) {
            ConnectionDotBadge(appearance: dotAppearance)
        }
    }

    /// VoiceOver announces the connected account identity; the hint names
    /// the local action.
    private var accessibilityName: String {
        if let displayName = profile.displayName, !displayName.isEmpty {
            return displayName
        }
        return "Google account"
    }
}

/// The account capsule's appearance — shared by the disconnected and
/// connected forms: the Planner shell with a visible
/// focus ring, and emphasis on keyboard focus, pointer hover, or press.
private struct AccountCapsuleButtonStyle: ButtonStyle {
    let emphasized: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Capsule()
                    .fill(Color.white.opacity(0.8))
                    .overlay {
                        Capsule()
                            .strokeBorder(PlannerPalette.separator, lineWidth: 1)
                    }
            }
            .background {
                Capsule()
                    .fill(PlannerPalette.emphasizedControl)
                    .opacity(configuration.isPressed || emphasized ? 1 : 0)
            }
            .overlay {
                if emphasized {
                    Capsule()
                        .strokeBorder(PlannerPalette.olive, lineWidth: 2)
                }
            }
    }
}

/// The circular account avatar: initials (or a neutral person glyph when
/// the account has no display name) always render underneath, and the
/// profile image covers them only once it has loaded, so a slow, missing,
/// or failed image never presents a broken image.
private struct ConnectedAccountAvatar: View {
    let profile: GoogleAccountConnection.GoogleConnectedProfile

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(PlannerPalette.olive)

            initialsContent

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipShape(Circle())
        .task(id: profile.imageURL) {
            await loadImage()
        }
    }

    @ViewBuilder
    private var initialsContent: some View {
        if initials.isEmpty {
            Image(systemName: "person.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        } else {
            Text(initials)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    /// Locale-aware initials from the display name, falling back to the
    /// name's first letter.
    private var initials: String {
        guard let displayName = profile.displayName, !displayName.isEmpty else {
            return ""
        }

        let formatter = PersonNameComponentsFormatter()
        if let components = formatter.personNameComponents(from: displayName) {
            formatter.style = .abbreviated
            return formatter.string(from: components)
        }
        return String(displayName.prefix(1)).uppercased()
    }

    /// Loads the profile image through an ephemeral session so Planner never
    /// persists account profile data to disk. Any failure leaves the
    /// initials fallback in place.
    private func loadImage() async {
        guard let url = profile.imageURL, image == nil else {
            return
        }

        let session = URLSession(configuration: .ephemeral)
        guard
            let (data, _) = try? await session.data(from: url),
            let loaded = UIImage(data: data)
        else {
            return
        }
        image = loaded
    }
}
