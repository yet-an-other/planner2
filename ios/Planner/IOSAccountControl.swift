import GoogleSignInSwift
import SwiftUI

/// The iOS Account Control across its connection presentations.
///
/// The disconnected presentation uses Google's supplied SwiftUI sign-in
/// button so branding, localization, and the disabled presentation stay
/// Google-owned. The wide labeled form appears only when it fits the width
/// the iOS Calendar Header offers; the icon form is used whenever the width
/// is constrained. While a connection attempt is in flight the supplied
/// disabled state prevents repeated activations.
///
/// The connected presentation is a compact Planner-styled capsule with the
/// account avatar — profile image when it loads, initials otherwise — and a
/// Disconnect on This Device affordance. One activation disconnects
/// immediately, without confirmation.
///
/// Every form provides at least a 44-point activation target and announces
/// its action to VoiceOver.
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
        case .connecting:
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
        .accessibilityLabel("Connect Google account")
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

/// The compact connected form: the account avatar beside a Disconnect on
/// This Device affordance in a Planner-styled capsule. One activation
/// disconnects immediately; there is no confirmation step.
private struct ConnectedAccountControl: View {
    let profile: GoogleAccountConnection.GoogleConnectedProfile
    let disconnectOnThisDevice: () -> Void

    var body: some View {
        Button(action: disconnectOnThisDevice) {
            HStack(spacing: 6) {
                ConnectedAccountAvatar(profile: profile)
                    .frame(width: 28, height: 28)

                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PlannerPalette.ink)
            }
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .frame(height: 36)
        }
        .buttonStyle(.plain)
        .background {
            Capsule()
                .fill(Color.white.opacity(0.8))
                .overlay {
                    Capsule().strokeBorder(PlannerPalette.separator, lineWidth: 1)
                }
        }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }

    /// VoiceOver announces the action and the connected account identity.
    private var accessibilityLabel: String {
        if let displayName = profile.displayName, !displayName.isEmpty {
            return "Disconnect \(displayName) on this device"
        }
        return "Disconnect Google account on this device"
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
