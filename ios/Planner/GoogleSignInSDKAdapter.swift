import GoogleSignIn
import UIKit

/// The production Google Sign-In adapter backed by the official SDK.
///
/// All SDK-specific details — the shared `GIDSignIn` instance, the
/// presenting view controller, profile extraction, and error
/// classification — stay inside this type; the module above the seam sees
/// only ``GoogleAuthorizationOutcome`` values.
///
/// Disconnect on This Device maps to the SDK's local `signOut()`. The SDK's
/// `disconnect()` revokes the project-wide Google Authorization Grant and is
/// never called here, keeping sibling Planner connections intact.
final class GoogleSignInSDKAdapter: GoogleSignInAdapting {
    /// Configures the SDK from Planner's validated build inputs. The client
    /// ID also arrives through the bundle's `GIDClientID` value; setting the
    /// configuration explicitly keeps the validated configuration the single
    /// source. No server client ID is set: this app performs no backend code
    /// exchange.
    init(configuration: GoogleAccountConnectionConfiguration.Configured) {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: configuration.clientID
        )
    }

    func signIn(
        requestingScopes scopes: [String]
    ) async -> GoogleAuthorizationOutcome {
        guard let presenter = Self.presentingViewController() else {
            return .unavailable(.failed)
        }

        do {
            // One authorization request carries identity and the Calendar
            // scope, so an existing project-wide grant is reused without a
            // redundant consent prompt and no incremental addScopes round
            // (and its already-granted error path) is needed.
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: presenter,
                hint: nil,
                additionalScopes: scopes
            )

            let profile = result.user.profile
            return .connected(
                GoogleAuthorizedAccount(
                    displayName: profile?.name,
                    imageURL: profile.flatMap(Self.profileImageURL),
                    grantedScopes: Set(result.user.grantedScopes ?? [])
                )
            )
        } catch {
            return Self.classify(error)
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }

    func handleCallbackURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    /// The profile image URL, requested large enough for the connected
    /// control's avatar on any display scale.
    private static func profileImageURL(
        from profile: GIDProfileData
    ) -> URL? {
        profile.hasImage ? profile.imageURL(withDimension: 128) : nil
    }

    /// Maps SDK and network errors to Planner-relevant outcomes. Raw Google
    /// errors never cross the seam.
    private static func classify(_ error: Error) -> GoogleAuthorizationOutcome {
        if let signInError = error as? GIDSignInError,
           signInError.code == .canceled
        {
            return .cancelled
        }

        if Self.isConnectivityFailure(error) {
            return .unavailable(.offline)
        }

        return .unavailable(.failed)
    }

    /// A transient connectivity failure may surface directly as a URL error
    /// or wrapped as the underlying cause of an SDK error.
    private static func isConnectivityFailure(_ error: Error) -> Bool {
        let connectivityCodes = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut,
        ]

        var current: NSError? = error as NSError
        while let error = current {
            if error.domain == NSURLErrorDomain,
               connectivityCodes.contains(error.code)
            {
                return true
            }
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    /// The view controller Google presents its authorization UI from: the
    /// key window's root in the active window scene.
    private static func presentingViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}
