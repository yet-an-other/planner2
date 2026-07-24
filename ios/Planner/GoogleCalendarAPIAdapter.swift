import Foundation
import GoogleSignIn

/// Percent-encoded Google Calendar API paths whose opaque identifiers must
/// remain one path segment.
enum GoogleCalendarAPIPath {
    static func events(sourceCalendarID: String) -> String? {
        guard !sourceCalendarID.isEmpty else {
            return nil
        }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        guard let encodedID = sourceCalendarID.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) else {
            return nil
        }
        return "/calendar/v3/calendars/\(encodedID)/events"
    }
}

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
    func fetchPrimarySourceCalendar() async -> GoogleSourceCalendarOutcome {
        do {
            let token = try await refreshedAccessToken()
            return .success(try await fetchPrimaryCalendar(token: token))
        } catch {
            return .unavailable(Self.classifyFailure(error))
        }
    }

    @MainActor
    func fetchEvents(
        from sourceCalendars: [GoogleSourceCalendar],
        start: Date,
        end: Date
    ) async -> GoogleCalendarEventsOutcome {
        do {
            let token = try await refreshedAccessToken()
            // Every supplied Source Calendar and all of its pages must arrive
            // before this aggregate crosses the seam. Event color metadata is
            // cosmetic, so its failure silently degrades to each event's
            // Source Calendar color.
            async let events = fetchAllEvents(
                token: token,
                sourceCalendars: sourceCalendars,
                from: start,
                to: end
            )
            async let colors = fetchEventColorBackgrounds(token: token)
            return .success(
                events: try await events,
                eventColorBackgrounds: (try? await colors) ?? [:]
            )
        } catch {
            return .unavailable(Self.classifyFailure(error))
        }
    }

    /// Returns one SDK-refreshed access token. Confirmed invalidation remains
    /// the Google Account Connection module's concern and crosses this seam
    /// only as a stable fetch failure.
    @MainActor
    private func refreshedAccessToken() async throws -> String {
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw FetchError.failed
        }
        try await user.refreshTokensIfNeeded()
        return user.accessToken.tokenString
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
        guard let id = entry.id else {
            throw FetchError.failed
        }
        return GoogleSourceCalendar(
            id: id,
            summary: entry.summary ?? "",
            backgroundColorHex: entry.backgroundColor ?? "#039BE5",
            isPrimary: entry.primary ?? false
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
        sourceCalendars: [GoogleSourceCalendar],
        from start: Date,
        to end: Date
    ) async throws -> [GoogleSourceCalendarEvent] {
        let stampFormatter = ISO8601DateFormatter()
        stampFormatter.formatOptions = [.withInternetDateTime]

        var events: [GoogleSourceCalendarEvent] = []
        for sourceCalendar in sourceCalendars {
            var pageToken: String?
            repeat {
                var query = [
                    URLQueryItem(
                        name: "timeMin",
                        value: stampFormatter.string(from: start)
                    ),
                    URLQueryItem(
                        name: "timeMax",
                        value: stampFormatter.string(from: end)
                    ),
                    // Recurring events arrive as individual instances.
                    URLQueryItem(name: "singleEvents", value: "true"),
                    URLQueryItem(name: "maxResults", value: "2500"),
                ]
                if let pageToken {
                    query.append(
                        URLQueryItem(name: "pageToken", value: pageToken)
                    )
                }

                guard let path = GoogleCalendarAPIPath.events(
                    sourceCalendarID: sourceCalendar.id
                ) else {
                    throw FetchError.failed
                }
                let page: EventsPageDTO = try await get(
                    path: path,
                    query: query,
                    token: token
                )
                events.append(
                    contentsOf: (page.items ?? []).compactMap(Self.mapEvent).map {
                        GoogleSourceCalendarEvent(
                            sourceCalendar: sourceCalendar,
                            event: $0
                        )
                    }
                )
                pageToken = page.nextPageToken
            } while pageToken != nil
        }

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
        components.percentEncodedPath = path
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
        let id: String?
        let summary: String?
        let backgroundColor: String?
        let primary: Bool?
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
            let displayName: String?
            let email: String?

            enum CodingKeys: String, CodingKey {
                case isSelf = "self"
                case responseStatus
                case displayName
                case email
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
        let htmlLink: String?
        let location: String?
        let description: String?
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
            } ?? false,
            googleLink: dto.htmlLink,
            location: dto.location,
            notes: dto.description,
            attendees: (dto.attendees ?? []).map {
                GoogleCalendarEventAttendee(
                    displayName: $0.displayName,
                    email: $0.email,
                    responseStatus: $0.responseStatus
                )
            }
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
    private static func classifyFailure(
        _ error: Error
    ) -> GoogleCalendarEventsFailure {
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
                return .offline
            }
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }

        return .failed
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
