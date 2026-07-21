import Foundation
import GoogleSignIn

/// The production Google Calendar adapter: it fetches the primary Source
/// Calendar's attributes and events directly from the Google Calendar API
/// with the Google Sign-In SDK-managed access token. Planner's backend is
/// never involved (iOS ADR 0001 — the web backend does not proxy calendar
/// data either), and raw Google or URL errors never cross the seam.
///
/// Fetches are memory-only by construction: responses decode straight into
/// seam values and nothing is written to disk (iOS ADR 0003).
final class GoogleCalendarAPIAdapter: GoogleCalendarEventsAdapting {
    private let session: URLSession

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    @MainActor
    func fetchEvents(
        from start: Date,
        to end: Date
    ) async -> GoogleCalendarEventsOutcome {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            // The model only fetches while connected; a missing user means
            // the connection left first.
            return .unavailable(.failed)
        }

        do {
            // The SDK refreshes the access token when it is near expiry;
            // confirmed invalidation is the connection module's concern,
            // surfaced here as an ordinary failure.
            try await user.refreshTokensIfNeeded()
        } catch {
            return Self.classify(error)
        }

        do {
            // Event content and calendar attributes must all arrive; the
            // color metadata is cosmetic, so its failure degrades to
            // Source Calendar colors instead of failing the fetch. The
            // token crosses the concurrent requests; the SDK user does
            // not.
            let token = user.accessToken.tokenString
            async let calendar = fetchPrimaryCalendar(token: token)
            async let events = fetchAllEvents(
                token: token,
                from: start,
                to: end
            )
            async let colors = fetchEventColorBackgrounds(token: token)
            return .success(
                calendar: try await calendar,
                events: try await events,
                eventColorBackgrounds: (try? await colors) ?? [:]
            )
        } catch {
            return Self.classify(error)
        }
    }

    // MARK: Requests

    private func fetchPrimaryCalendar(
        token: String
    ) async throws -> GoogleSourceCalendar {
        let entry: CalendarListEntryDTO = try await get(
            path: "/calendar/v3/users/me/calendarList/primary",
            query: [],
            token: token
        )
        return GoogleSourceCalendar(
            backgroundColorHex: entry.backgroundColor ?? "#039BE5"
        )
    }

    /// Google's event color metadata: each explicit event color id to its
    /// background `#RRGGBB` hex, from the account-wide colors resource.
    private func fetchEventColorBackgrounds(
        token: String
    ) async throws -> [String: String] {
        let dto: ColorsDTO = try await get(
            path: "/calendar/v3/colors",
            query: [],
            token: token
        )
        return (dto.event ?? [:]).compactMapValues(\.background)
    }

    private func fetchAllEvents(
        token: String,
        from start: Date,
        to end: Date
    ) async throws -> [GoogleCalendarEvent] {
        let stampFormatter = ISO8601DateFormatter()
        stampFormatter.formatOptions = [.withInternetDateTime]

        var events: [GoogleCalendarEvent] = []
        var pageToken: String?
        repeat {
            var query = [
                URLQueryItem(name: "timeMin", value: stampFormatter.string(from: start)),
                URLQueryItem(name: "timeMax", value: stampFormatter.string(from: end)),
                // Recurring events arrive as individual instances.
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "maxResults", value: "2500"),
            ]
            if let pageToken {
                query.append(URLQueryItem(name: "pageToken", value: pageToken))
            }

            let page: EventsPageDTO = try await get(
                path: "/calendar/v3/calendars/primary/events",
                query: query,
                token: token
            )
            events.append(contentsOf: (page.items ?? []).compactMap(Self.mapEvent))
            pageToken = page.nextPageToken
        } while pageToken != nil

        return events
    }

    private func get<D: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem],
        token: String
    ) async throws -> D {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.googleapis.com"
        components.path = path
        components.queryItems = query
        guard let url = components.url else {
            throw FetchError.failed
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode)
        else {
            throw FetchError.failed
        }

        do {
            return try JSONDecoder().decode(D.self, from: data)
        } catch {
            throw FetchError.failed
        }
    }

    // MARK: Decoding

    private enum FetchError: Error {
        case failed
    }

    private struct CalendarListEntryDTO: Decodable, Sendable {
        let backgroundColor: String?
    }

    private struct EventsPageDTO: Decodable, Sendable {
        let items: [EventDTO]?
        let nextPageToken: String?
    }

    private struct ColorsDTO: Decodable, Sendable {
        struct ColorDefinition: Decodable, Sendable {
            let background: String?
        }

        let event: [String: ColorDefinition]?
    }

    private struct EventDTO: Decodable, Sendable {
        struct Point: Decodable, Sendable {
            let date: String?
            let dateTime: String?
        }

        struct Attendee: Decodable, Sendable {
            let isSelf: Bool?
            let responseStatus: String?

            enum CodingKeys: String, CodingKey {
                case isSelf = "self"
                case responseStatus
            }
        }

        let id: String?
        let iCalUID: String?
        let status: String?
        let summary: String?
        let colorId: String?
        let start: Point?
        let end: Point?
        let attendees: [Attendee]?
    }

    /// Maps one decoded event into the seam's Google-shaped value, dropping
    /// events without a usable same-kind start/end pair.
    private static func mapEvent(_ dto: EventDTO) -> GoogleCalendarEvent? {
        guard
            let start = mapPoint(dto.start),
            let end = mapPoint(dto.end),
            start.sameKind(as: end)
        else {
            return nil
        }

        let summary = dto.summary
        return GoogleCalendarEvent(
            id: dto.id ?? dto.iCalUID ?? "\(start)-\(summary ?? "")",
            summary: summary,
            colorId: dto.colorId,
            start: start,
            end: end,
            isCancelled: dto.status == "cancelled",
            isDeclinedByViewer: dto.attendees?.contains {
                $0.isSelf == true && $0.responseStatus == "declined"
            } ?? false
        )
    }

    private static func mapPoint(
        _ point: EventDTO.Point?
    ) -> GoogleCalendarEventTime? {
        if let date = point?.date {
            // All-day points arrive as "yyyy-MM-dd" civil dates.
            let parts = date.split(separator: "-")
            guard
                parts.count == 3,
                let year = Int(parts[0]),
                let month = Int(parts[1]),
                let day = Int(parts[2])
            else {
                return nil
            }
            return .allDay(year: year, month: month, day: day)
        }

        if let dateTime = point?.dateTime {
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds,
            ]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            guard
                let instant = withFractional.date(from: dateTime)
                    ?? plain.date(from: dateTime)
            else {
                return nil
            }
            return .timed(instant)
        }

        return nil
    }

    /// Maps failures to Planner-relevant outcomes: connectivity loss is
    /// transient; anything else is a generic failure. Raw errors never
    /// cross the seam.
    private static func classify(_ error: Error) -> GoogleCalendarEventsOutcome {
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
                return .unavailable(.offline)
            }
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }

        return .unavailable(.failed)
    }
}

private extension GoogleCalendarEventTime {
    func sameKind(as other: GoogleCalendarEventTime) -> Bool {
        switch (self, other) {
        case (.allDay, .allDay), (.timed, .timed):
            return true
        default:
            return false
        }
    }
}
