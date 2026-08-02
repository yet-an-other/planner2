import Foundation
import Testing
@testable import Planner

/// Direct coverage of Calendar Event Normalization (Planning glossary) at
/// its own interface: fetched Google Calendar events in, classified
/// Calendar Events out. These tests pin the product rules the interface
/// owns — drop-out, deduplication, Event Color resolution, and bar/row
/// classification — without driving the fetch pipeline.
@Suite("Calendar Event Normalization")
struct CalendarEventNormalizationTests {
    private static let primary = GoogleSourceCalendar(
        id: "primary@example.com",
        summary: "Primary",
        backgroundColorHex: "#039BE5",
        isPrimary: true
    )
    private static let family = GoogleSourceCalendar(
        id: "family@example.com",
        summary: "Family",
        backgroundColorHex: "#7CB342",
        isPrimary: false
    )

    private static func makeEnvironment(
        timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!
    ) -> CalendarEnvironment {
        CalendarEnvironment(
            now: Date(timeIntervalSince1970: 1_784_116_800),
            calendar: Calendar(identifier: .gregorian),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone
        )
    }

    private static func gmt(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    private static func event(
        id: String,
        iCalUID: String? = nil,
        originalStartTime: GoogleCalendarEventTime? = nil,
        summary: String? = "Event",
        colorId: String? = nil,
        start: GoogleCalendarEventTime,
        end: GoogleCalendarEventTime,
        isCancelled: Bool = false,
        isDeclinedByViewer: Bool = false,
        source: GoogleSourceCalendar = primary
    ) -> GoogleSourceCalendarEvent {
        GoogleSourceCalendarEvent(
            sourceCalendar: source,
            event: GoogleCalendarEvent(
                id: id,
                iCalUID: iCalUID,
                originalStartTime: originalStartTime,
                summary: summary,
                colorId: colorId,
                start: start,
                end: end,
                isCancelled: isCancelled,
                isDeclinedByViewer: isDeclinedByViewer
            )
        )
    }

    @Test("Cancelled and declined events drop out")
    func cancelledAndDeclinedDropOut() {
        let events = CalendarEventNormalization.normalize(
            [
                Self.event(
                    id: "cancelled",
                    start: .allDay(year: 2026, month: 7, day: 20),
                    end: .allDay(year: 2026, month: 7, day: 21),
                    isCancelled: true
                ),
                Self.event(
                    id: "declined",
                    start: .allDay(year: 2026, month: 7, day: 20),
                    end: .allDay(year: 2026, month: 7, day: 21),
                    isDeclinedByViewer: true
                ),
                Self.event(
                    id: "kept",
                    start: .allDay(year: 2026, month: 7, day: 20),
                    end: .allDay(year: 2026, month: 7, day: 21)
                ),
            ],
            eventColorBackgrounds: [:],
            environment: Self.makeEnvironment()
        )
        #expect(events.map(\.id) == [
            "src:primary@example.com:event:kept"
        ])
    }

    @Test("Duplicate copies of one occurrence collapse to the Primary copy intact")
    func duplicateCopiesCollapseToPrimaryCopy() {
        let events = CalendarEventNormalization.normalize(
            [
                // The Family copy arrives first; the Primary copy still
                // wins, and no field is combined across copies.
                Self.event(
                    id: "invite-family",
                    iCalUID: "uid-invite@google.com",
                    summary: "Family copy",
                    start: .timed(Self.gmt(2026, 7, 21, 9)),
                    end: .timed(Self.gmt(2026, 7, 21, 10)),
                    source: Self.family
                ),
                Self.event(
                    id: "invite-primary",
                    iCalUID: "uid-invite@google.com",
                    summary: "Primary copy",
                    start: .timed(Self.gmt(2026, 7, 21, 9)),
                    end: .timed(Self.gmt(2026, 7, 21, 10))
                ),
            ],
            eventColorBackgrounds: [:],
            environment: Self.makeEnvironment()
        )
        #expect(events.count == 1)
        #expect(events.first?.title == "Primary copy")
        #expect(events.first?.sourceCalendar == Self.primary)
    }

    @Test("A blank title becomes Busy; missing and padded titles follow the same rule")
    func blankTitleBecomesBusy() {
        let events = CalendarEventNormalization.normalize(
            [
                Self.event(
                    id: "untitled",
                    summary: "   ",
                    start: .timed(Self.gmt(2026, 7, 21, 9)),
                    end: .timed(Self.gmt(2026, 7, 21, 10))
                ),
                Self.event(
                    id: "missing",
                    summary: nil,
                    start: .timed(Self.gmt(2026, 7, 21, 9)),
                    end: .timed(Self.gmt(2026, 7, 21, 10))
                ),
                Self.event(
                    id: "padded",
                    summary: "  Standup  ",
                    start: .timed(Self.gmt(2026, 7, 21, 9)),
                    end: .timed(Self.gmt(2026, 7, 21, 10))
                ),
            ],
            eventColorBackgrounds: [:],
            environment: Self.makeEnvironment()
        )
        #expect(events.map(\.title) == ["Busy", "Busy", "Standup"])
    }

    @Test("Without a Primary copy the deterministic-first Source Calendar wins")
    func deterministicFirstSourceWins() {
        let events = CalendarEventNormalization.normalize(
            [
                Self.event(
                    id: "invite-family",
                    iCalUID: "uid-invite@google.com",
                    summary: "Family copy",
                    start: .timed(Self.gmt(2026, 7, 21, 9)),
                    end: .timed(Self.gmt(2026, 7, 21, 10)),
                    source: Self.family
                ),
                Self.event(
                    id: "invite-other",
                    iCalUID: "uid-invite@google.com",
                    summary: "Other copy",
                    start: .timed(Self.gmt(2026, 7, 21, 9)),
                    end: .timed(Self.gmt(2026, 7, 21, 10)),
                    source: GoogleSourceCalendar(
                        id: "zzz-other@example.com",
                        summary: "Other",
                        backgroundColorHex: "#8E24AA",
                        isPrimary: false
                    )
                ),
            ],
            eventColorBackgrounds: [:],
            environment: Self.makeEnvironment()
        )
        #expect(events.count == 1)
        #expect(events.first?.title == "Family copy")
    }

    @Test("Separate instances of a recurring event never collapse")
    func recurringInstancesNeverCollapse() {
        let events = CalendarEventNormalization.normalize(
            [
                Self.event(
                    id: "standup-1",
                    iCalUID: "uid-standup@google.com",
                    start: .timed(Self.gmt(2026, 7, 21, 9)),
                    end: .timed(Self.gmt(2026, 7, 21, 9, 15))
                ),
                Self.event(
                    id: "standup-2",
                    iCalUID: "uid-standup@google.com",
                    start: .timed(Self.gmt(2026, 7, 22, 9)),
                    end: .timed(Self.gmt(2026, 7, 22, 9, 15))
                ),
            ],
            eventColorBackgrounds: [:],
            environment: Self.makeEnvironment()
        )
        #expect(events.count == 2)
    }

    @Test("A moved instance never collapses with the occurrence at its current start")
    func movedInstanceNeverCollapses() {
        let events = CalendarEventNormalization.normalize(
            [
                // The moved instance carries its original slot.
                Self.event(
                    id: "standup-moved",
                    iCalUID: "uid-standup@google.com",
                    originalStartTime: .timed(Self.gmt(2026, 7, 21, 9)),
                    start: .timed(Self.gmt(2026, 7, 22, 9)),
                    end: .timed(Self.gmt(2026, 7, 22, 9, 15))
                ),
                // Another occurrence now occupies that slot.
                Self.event(
                    id: "standup-current",
                    iCalUID: "uid-standup@google.com",
                    start: .timed(Self.gmt(2026, 7, 22, 9)),
                    end: .timed(Self.gmt(2026, 7, 22, 9, 15))
                ),
            ],
            eventColorBackgrounds: [:],
            environment: Self.makeEnvironment()
        )
        #expect(events.count == 2)
    }

    @Test("A missing iCalUID never guesses duplicates across sources")
    func missingICalUIDNeverGuesses() {
        let events = CalendarEventNormalization.normalize(
            [
                Self.event(
                    id: "same-google-id",
                    start: .timed(Self.gmt(2026, 7, 21, 9)),
                    end: .timed(Self.gmt(2026, 7, 21, 10))
                ),
                Self.event(
                    id: "same-google-id",
                    start: .timed(Self.gmt(2026, 7, 21, 9)),
                    end: .timed(Self.gmt(2026, 7, 21, 10)),
                    source: Self.family
                ),
            ],
            eventColorBackgrounds: [:],
            environment: Self.makeEnvironment()
        )
        // Without an iCalUID the Source Calendar ID is part of the
        // identity, so same-looking events across calendars stay separate.
        #expect(events.count == 2)
    }

    @Test("An all-day event's exclusive end turns inclusive")
    func allDayEndTurnsInclusive() {
        let events = CalendarEventNormalization.normalize(
            [
                Self.event(
                    id: "conference",
                    start: .allDay(year: 2026, month: 7, day: 20),
                    end: .allDay(year: 2026, month: 7, day: 23)
                ),
            ],
            eventColorBackgrounds: [:],
            environment: Self.makeEnvironment()
        )
        guard case .bar(let startDate, let endDate, _) = events.first?.kind
        else {
            Issue.record("an all-day event must classify as a bar")
            return
        }
        #expect(startDate == Self.gmt(2026, 7, 20))
        // Google's exclusive end (Jul 23) means the event's last day is
        // Jul 22.
        #expect(endDate == Self.gmt(2026, 7, 22))
    }

    @Test("A same-day timed event classifies as a row; a multi-day one as a bar")
    func timedClassification() {
        let events = CalendarEventNormalization.normalize(
            [
                Self.event(
                    id: "standup",
                    start: .timed(Self.gmt(2026, 7, 21, 9)),
                    end: .timed(Self.gmt(2026, 7, 21, 9, 15))
                ),
                Self.event(
                    id: "overnight",
                    start: .timed(Self.gmt(2026, 7, 21, 22)),
                    end: .timed(Self.gmt(2026, 7, 22, 6))
                ),
            ],
            eventColorBackgrounds: [:],
            environment: Self.makeEnvironment()
        )
        guard case .row(let rowDate, _, let startTimeText) = events[0].kind
        else {
            Issue.record("a same-day timed event must classify as a row")
            return
        }
        #expect(rowDate == Self.gmt(2026, 7, 21))
        #expect(!startTimeText.isEmpty)
        guard case .bar = events[1].kind else {
            Issue.record("a multi-day timed event must classify as a bar")
            return
        }
    }

    @Test("Classification uses the environment's local dates, not GMT's")
    func classificationIsLocal() {
        // 22:30 GMT is already the next day at GMT+2.
        let plusTwo = TimeZone(secondsFromGMT: 2 * 3600)!
        let events = CalendarEventNormalization.normalize(
            [
                Self.event(
                    id: "late",
                    start: .timed(Self.gmt(2026, 7, 21, 22, 30)),
                    end: .timed(Self.gmt(2026, 7, 21, 23, 30))
                ),
            ],
            eventColorBackgrounds: [:],
            environment: Self.makeEnvironment(timeZone: plusTwo)
        )
        guard case .row(let date, _, _) = events.first?.kind else {
            Issue.record("a same-day timed event must classify as a row")
            return
        }
        // Local midnight at GMT+2 is 22:00 GMT on the prior day.
        #expect(date == Self.gmt(2026, 7, 21, 22))
    }

    @Test("An explicit Google event color wins; the Source Calendar background is the fallback")
    func eventColorResolution() {
        let events = CalendarEventNormalization.normalize(
            [
                Self.event(
                    id: "explicit",
                    colorId: "9",
                    start: .allDay(year: 2026, month: 7, day: 20),
                    end: .allDay(year: 2026, month: 7, day: 21)
                ),
                Self.event(
                    id: "fallback",
                    start: .allDay(year: 2026, month: 7, day: 20),
                    end: .allDay(year: 2026, month: 7, day: 21)
                ),
                // An unknown color id falls back to the calendar's
                // background, as an absent one does.
                Self.event(
                    id: "unknown-color",
                    colorId: "not-a-color",
                    start: .allDay(year: 2026, month: 7, day: 20),
                    end: .allDay(year: 2026, month: 7, day: 21)
                ),
            ],
            eventColorBackgrounds: ["9": "#4285F4"],
            environment: Self.makeEnvironment()
        )
        #expect(events[0].colorHex == "#4285F4")
        #expect(events[1].colorHex == Self.primary.backgroundColorHex)
        #expect(events[2].colorHex == Self.primary.backgroundColorHex)
    }

    @Test("Canonical identity pins the iCalUID occurrence and fallback forms")
    func canonicalIdentity() {
        let recurring = Self.event(
            id: "instance-3",
            iCalUID: "uid-standup@google.com",
            originalStartTime: .timed(Self.gmt(2026, 7, 21, 9)),
            start: .timed(Self.gmt(2026, 7, 22, 9)),
            end: .timed(Self.gmt(2026, 7, 22, 9, 15))
        )
        #expect(
            CalendarEventCanonicalIdentity.id(of: recurring)
                == "ical:uid-standup@google.com:occurrence:time-\(Self.gmt(2026, 7, 21, 9).timeIntervalSince1970)"
        )
        let plain = Self.event(
            id: "plain",
            start: .allDay(year: 2026, month: 7, day: 20),
            end: .allDay(year: 2026, month: 7, day: 21)
        )
        #expect(
            CalendarEventCanonicalIdentity.id(of: plain)
                == "src:primary@example.com:event:plain"
        )
    }

    @Test("A snapshot encoded before the Calendar Event merge still decodes")
    func preMergeSnapshotFormatDecodes() throws {
        // The pre-merge StoredCalendarEvent record, byte-for-byte in the
        // shape FileStoredCalendarEventsStore wrote: the merged
        // CalendarEvent kept every field name and Kind case label, so
        // existing devices' snapshots survive the upgrade (ADR 0007's
        // always-stale semantics are the safety net, not the plan).
        let legacyJSON = """
        {
          "accountID": "google-account-1",
          "events": [
            {
              "id": "ical:uid-conference@google.com:occurrence:date-2026-7-20",
              "sourceCalendar": {
                "id": "primary@example.com",
                "summary": "Primary",
                "backgroundColorHex": "#039BE5",
                "isPrimary": true
              },
              "title": "Conference",
              "colorHex": "#039BE5",
              "textTone": {"light": {}},
              "kind": {
                "bar": {
                  "startDate": 815788800,
                  "endDate": 815961600,
                  "startsAt": 815788800
                }
              },
              "detail": {
                "title": "Conference",
                "colorHex": "#039BE5",
                "timingText": "All day · Jul 20, 2026 – Jul 22, 2026",
                "location": "Berlin",
                "googleLink": "https://calendar.google.com/event?eid=abc",
                "notes": "Bring badge",
                "attendees": [],
                "hiddenAttendeeCount": 3
              }
            },
            {
              "id": "src:primary@example.com:event:standup",
              "sourceCalendar": {
                "id": "primary@example.com",
                "summary": "Primary",
                "backgroundColorHex": "#039BE5",
                "isPrimary": true
              },
              "title": "Standup",
              "colorHex": "#7CB342",
              "textTone": {"dark": {}},
              "kind": {
                "row": {
                  "date": 815788800,
                  "startsAt": 815824400,
                  "startTimeText": "9:00 AM"
                }
              },
              "detail": {
                "title": "Standup",
                "colorHex": "#7CB342",
                "timingText": "Mon, Jul 20, 2026 · 9:00 – 9:15 AM",
                "attendees": [],
                "hiddenAttendeeCount": 0
              }
            }
          ]
        }
        """
        let snapshot = try JSONDecoder().decode(
            StoredCalendarEventsSnapshot.self,
            from: Data(legacyJSON.utf8)
        )
        #expect(snapshot.accountID == "google-account-1")
        #expect(snapshot.events.count == 2)
        #expect(snapshot.events[0].title == "Conference")
        guard case .bar = snapshot.events[0].kind else {
            Issue.record("the legacy bar record must decode as a bar")
            return
        }
        guard case .row(_, _, let startTimeText) = snapshot.events[1].kind
        else {
            Issue.record("the legacy row record must decode as a row")
            return
        }
        #expect(startTimeText == "9:00 AM")
        #expect(snapshot.events[0].detail.location == "Berlin")
    }

    @Test("The text tone follows the resolved Event Color")
    func textToneFollowsResolvedColor() {
        let events = CalendarEventNormalization.normalize(
            [
                // The Family background ranks dark text (iOS ADR 0004).
                Self.event(
                    id: "family-event",
                    start: .allDay(year: 2026, month: 7, day: 20),
                    end: .allDay(year: 2026, month: 7, day: 21),
                    source: Self.family
                ),
            ],
            eventColorBackgrounds: [:],
            environment: Self.makeEnvironment()
        )
        #expect(events.first?.colorHex == Self.family.backgroundColorHex)
        #expect(
            events.first?.textTone
                == CalendarEventNormalization.textTone(
                    forHexColor: Self.family.backgroundColorHex
                )
        )
    }

    @Test("Text tone ranks Planner's ink against white by APCA contrast")
    func textToneRanking() {
        // Google's blue reads white; a pale yellow reads ink (iOS ADR
        // 0004).
        #expect(
            CalendarEventNormalization.textTone(forHexColor: "#039BE5")
                == .light
        )
        #expect(
            CalendarEventNormalization.textTone(forHexColor: "#F6BF26")
                == .dark
        )
        // #5F83E6: ink out-rates white on the WCAG 2.x ratio yet visibly
        // reads worse — the case APCA ranking exists for (iOS ADR 0004).
        #expect(
            CalendarEventNormalization.textTone(forHexColor: "#5F83E6")
                == .light
        )
        // An unparseable color reads as white text, matching the
        // pre-extraction fallback.
        #expect(
            CalendarEventNormalization.textTone(forHexColor: "not-hex")
                == .light
        )
    }
}
