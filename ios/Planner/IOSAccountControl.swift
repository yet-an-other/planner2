import GoogleSignInSwift
import SwiftUI

/// The iOS Account Control across its connection presentations.
///
/// The disconnected presentation uses Google's supplied SwiftUI sign-in
/// button so branding, localization, and the disabled presentation stay
/// Google-owned. The wide labeled form appears only when it fits the width
/// the iOS Calendar Header offers; the icon form is used whenever the width
/// is constrained. While restoration or a connection attempt is in flight,
/// the supplied disabled state prevents a false Connect and repeated
/// activations.
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
            disconnectedControl(connectEnabled: connectEnabled)
        case .restoring, .connecting:
            // Restoration and interactive Connect both present Google's
            // disabled state: no false Connect, no repeated activation.
            disconnectedControl(connectEnabled: false)
        case .connected(let profile):
            ConnectedAccountControl(
                profile: profile,
                disconnectOnThisDevice: disconnectOnThisDevice
            )
        }
    }

    private func disconnectedControl(connectEnabled: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            googleButton(style: .wide, enabled: connectEnabled)
                .fixedSize()
            googleButton(style: .icon, enabled: connectEnabled)
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .hoverEffect()
        // The label leads with Google's visible button text so VoiceOver
        // and Voice Control match what sighted users see; the hint names
        // Planner's action.
        .accessibilityLabel("Sign in with Google")
        .accessibilityHint("Connects your Google account")
    }

    private func googleButton(
        style: GoogleSignInButtonStyle,
        enabled: Bool
    ) -> some View {
        GoogleSignInButton(
            scheme: .light,
            style: style,
            state: enabled ? .normal : .disabled,
            action: connect
        )
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
            ConnectedAccountButtonStyle(emphasized: focused || hovered)
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

/// The connected capsule's appearance: the Planner shell with a visible
/// focus ring, and emphasis on keyboard focus, pointer hover, or press.
private struct ConnectedAccountButtonStyle: ButtonStyle {
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
