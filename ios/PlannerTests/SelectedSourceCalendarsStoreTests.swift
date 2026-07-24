import Foundation
import Testing
@testable import Planner

@Suite("Selected Source Calendars Store")
struct SelectedSourceCalendarsStoreTests {
    @Test("Selections survive relaunch and remain isolated by account")
    func relaunchAndAccountIsolation() {
        let defaults = makeEphemeralUserDefaults()
        let store = UserDefaultsSelectedSourceCalendarsStore(defaults: defaults)

        store.saveSelectedSourceCalendarIDs(
            ["primary", "shared-team"],
            for: "account-a"
        )
        store.saveSelectedSourceCalendarIDs(
            ["family"],
            for: "account-b"
        )

        let relaunchedStore = UserDefaultsSelectedSourceCalendarsStore(
            defaults: defaults
        )
        #expect(
            relaunchedStore.selectedSourceCalendarIDs(for: "account-a")
                == ["primary", "shared-team"]
        )
        #expect(
            relaunchedStore.selectedSourceCalendarIDs(for: "account-b")
                == ["family"]
        )
        #expect(
            relaunchedStore.selectedSourceCalendarIDs(for: "account-c") == nil
        )
    }

    @Test("An explicitly empty selection remains distinct from missing data")
    func emptySelection() {
        let store = UserDefaultsSelectedSourceCalendarsStore(
            defaults: makeEphemeralUserDefaults()
        )

        store.saveSelectedSourceCalendarIDs([], for: "account-a")

        #expect(store.selectedSourceCalendarIDs(for: "account-a") == [])
        #expect(store.selectedSourceCalendarIDs(for: "account-b") == nil)
    }

    @Test("Duplicate IDs normalize without changing their accepted order")
    func duplicateIDs() {
        let store = UserDefaultsSelectedSourceCalendarsStore(
            defaults: makeEphemeralUserDefaults()
        )

        store.saveSelectedSourceCalendarIDs(
            ["work", "family", "work", "family", "shared"],
            for: "account-a"
        )

        #expect(
            store.selectedSourceCalendarIDs(for: "account-a")
                == ["work", "family", "shared"]
        )
    }

    @Test("Malformed account values fail locally without leaking another account")
    func malformedAccountValue() {
        let defaults = makeEphemeralUserDefaults()
        defaults.set(
            [
                "valid-account": ["primary", "team"],
                "wrong-type": "primary",
                "mixed-types": ["primary", 42] as [Any],
                "blank-id": ["primary", "   "],
                "duplicates": ["one", "one", "two"],
            ],
            forKey: UserDefaultsSelectedSourceCalendarsStore.storageKey
        )
        let store = UserDefaultsSelectedSourceCalendarsStore(defaults: defaults)

        #expect(
            store.selectedSourceCalendarIDs(for: "valid-account")
                == ["primary", "team"]
        )
        #expect(store.selectedSourceCalendarIDs(for: "wrong-type") == nil)
        #expect(store.selectedSourceCalendarIDs(for: "mixed-types") == nil)
        #expect(store.selectedSourceCalendarIDs(for: "blank-id") == nil)
        #expect(
            store.selectedSourceCalendarIDs(for: "duplicates")
                == ["one", "two"]
        )
        #expect(store.selectedSourceCalendarIDs(for: "missing-account") == nil)
    }

    @Test("A malformed root and invalid account identifiers fail safely")
    func malformedRootAndAccountID() {
        let defaults = makeEphemeralUserDefaults()
        defaults.set(
            ["not", "an", "account", "dictionary"],
            forKey: UserDefaultsSelectedSourceCalendarsStore.storageKey
        )
        let store = UserDefaultsSelectedSourceCalendarsStore(defaults: defaults)

        #expect(store.selectedSourceCalendarIDs(for: "account-a") == nil)
        #expect(store.selectedSourceCalendarIDs(for: "") == nil)

        store.saveSelectedSourceCalendarIDs(["primary"], for: "   ")
        #expect(
            defaults.object(
                forKey: UserDefaultsSelectedSourceCalendarsStore.storageKey
            ) as? [String] == ["not", "an", "account", "dictionary"]
        )
    }

    @Test("Saving persists only opaque account and Source Calendar IDs")
    func narrowPersistedShape() {
        let defaults = makeEphemeralUserDefaults()
        let store = UserDefaultsSelectedSourceCalendarsStore(defaults: defaults)

        store.saveSelectedSourceCalendarIDs(
            ["calendar-id-1", "calendar-id-2"],
            for: "opaque-account-id"
        )

        let persisted = defaults.dictionary(
            forKey: UserDefaultsSelectedSourceCalendarsStore.storageKey
        )
        #expect(persisted?.count == 1)
        #expect(
            persisted?["opaque-account-id"] as? [String]
                == ["calendar-id-1", "calendar-id-2"]
        )
    }

    @Test("Clearing removes every account selection")
    func clearAllAccounts() {
        let defaults = makeEphemeralUserDefaults()
        let store = UserDefaultsSelectedSourceCalendarsStore(defaults: defaults)
        store.saveSelectedSourceCalendarIDs(["primary"], for: "account-a")
        store.saveSelectedSourceCalendarIDs(["family"], for: "account-b")

        store.clearAllSelectedSourceCalendars()

        #expect(store.selectedSourceCalendarIDs(for: "account-a") == nil)
        #expect(store.selectedSourceCalendarIDs(for: "account-b") == nil)
        #expect(
            defaults.object(
                forKey: UserDefaultsSelectedSourceCalendarsStore.storageKey
            ) == nil
        )
    }
}
