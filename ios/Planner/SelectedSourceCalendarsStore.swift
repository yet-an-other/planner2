import Foundation

/// The narrow persistence boundary for Selected Source Calendars.
///
/// Implementations store only stable Source Calendar IDs under Google's
/// stable opaque account identifier. Source Calendar summaries, colors,
/// Calendar Events, profile fields, and credentials cannot cross this seam.
protocol SelectedSourceCalendarsStoring {
    /// Loads the stored Source Calendar IDs for one account. `nil` means the
    /// account has no valid stored selection; an empty array is a valid
    /// persisted zero-source selection.
    func selectedSourceCalendarIDs(for accountID: String) -> [String]?

    /// Replaces one account's stored Source Calendar IDs.
    func saveSelectedSourceCalendarIDs(_ calendarIDs: [String], for accountID: String)

    /// Clears every account's selection at the installation boundary.
    func clearAllSelectedSourceCalendars()
}

/// The production app-local Selected Source Calendars store.
///
/// One fixed UserDefaults key holds a property-list dictionary whose keys are
/// opaque account identifiers and whose values are arrays of opaque Source
/// Calendar IDs. The shape is JSON-compatible, remains local to this app,
/// and lets the installation boundary clear all accounts atomically.
struct UserDefaultsSelectedSourceCalendarsStore: SelectedSourceCalendarsStoring {
    static let storageKey = "PlannerSelectedSourceCalendarsByAccount"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func selectedSourceCalendarIDs(for accountID: String) -> [String]? {
        guard Self.isValidIdentifier(accountID),
              let accounts = defaults.dictionary(forKey: Self.storageKey),
              let storedValue = accounts[accountID],
              let storedIDs = storedValue as? [Any]
        else {
            return nil
        }

        var seen = Set<String>()
        var calendarIDs: [String] = []
        calendarIDs.reserveCapacity(storedIDs.count)

        for storedID in storedIDs {
            guard let calendarID = storedID as? String,
                  Self.isValidIdentifier(calendarID)
            else {
                return nil
            }
            if seen.insert(calendarID).inserted {
                calendarIDs.append(calendarID)
            }
        }
        return calendarIDs
    }

    func saveSelectedSourceCalendarIDs(
        _ calendarIDs: [String],
        for accountID: String
    ) {
        guard Self.isValidIdentifier(accountID) else {
            return
        }

        var seen = Set<String>()
        let normalizedIDs = calendarIDs.filter {
            Self.isValidIdentifier($0) && seen.insert($0).inserted
        }

        var accounts = defaults.dictionary(forKey: Self.storageKey) ?? [:]
        accounts[accountID] = normalizedIDs
        defaults.set(accounts, forKey: Self.storageKey)
    }

    func clearAllSelectedSourceCalendars() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    private static func isValidIdentifier(_ identifier: String) -> Bool {
        !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
