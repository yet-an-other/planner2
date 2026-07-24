# Persist Selected Source Calendars per account on this device

Planner persists each Google account's Selected Source Calendars in app-local `UserDefaults`, keyed by Google's stable opaque account identifier. This is a narrow exception to ADR 0003's broad prohibition on stored Calendar data: only the account key and stable Source Calendar IDs are stored; Calendar Events and Source Calendar presentation data remain memory-only.

The selection survives relaunch and Disconnect on This Device so reconnecting the same account restores the user's configuration. Planner clears all selections when its installation boundary detects a fresh installation or migration to different hardware; Keychain was rejected because its uninstall lifetime conflicts with that boundary.

This account-linked Calendar configuration must be reflected in Planner's connection disclosure and App Privacy review.
