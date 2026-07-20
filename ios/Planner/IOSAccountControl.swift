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
        switch presentation {
        case .disconnected(let connectEnabled):
            DisconnectedAccountControl(
                connectEnabled: connectEnabled,
                connect: connect
            )
        case .restoring, .connecting:
            // Restoration and interactive Connect both present the dimmed,
            // non-interactive capsule: no false Connect, no repeated
            // activation.
            DisconnectedAccountControl(
                connectEnabled: false,
                connect: connect
            )
        case .connected(let profile):
            ConnectedAccountControl(
                profile: profile,
                disconnectOnThisDevice: disconnectOnThisDevice
            )
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
    }
}

/// The connected form: the account avatar and the Disconnect on This
/// Device affordance in a Planner-styled capsule, with the display name
/// only when the measured width fits it — the compact form takes over
/// before the capsule could crowd the centered Visible Month. One
/// activation disconnects immediately; there is no confirmation step.
private struct ConnectedAccountControl: View {
    let profile: GoogleAccountConnection.GoogleConnectedProfile
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
