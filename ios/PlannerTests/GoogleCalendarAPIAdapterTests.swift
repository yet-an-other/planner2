import Foundation
import Testing
@testable import Planner

private actor CalendarListTransport {
    private(set) var requests: [URLRequest] = []

    func load(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let components = URLComponents(
            url: request.url!,
            resolvingAgainstBaseURL: false
        )
        let pageToken = components?.queryItems?.first {
            $0.name == "pageToken"
        }?.value

        let json: String
        if pageToken == nil {
            json = """
            {
              "items": [
                {"id":"primary","summary":" Personal ","backgroundColor":"#039BE5","primary":true,"accessRole":"owner"},
                {"id":"hidden","summary":"Hidden","hidden":true,"accessRole":"reader"},
                {"id":"deleted","summary":"Deleted","deleted":true,"accessRole":"owner"},
                {"id":"busy","summary":"Busy only","accessRole":"freeBusyReader"},
                {"id":"unknown","summary":"Unknown","accessRole":"mystery"}
              ],
              "nextPageToken": "page-two"
            }
            """
        } else if pageToken == "page-two" {
            json = """
            {
              "items": [
                {"id":"team","summary":"Team","backgroundColor":"#7CB342","accessRole":"reader"},
                {"id":"write","summary":"Write","accessRole":"writer"}
              ]
            }
            """
        } else {
            throw URLError(.badServerResponse)
        }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(json.utf8), response)
    }
}

@Suite("Google Calendar API Adapter")
@MainActor
struct GoogleCalendarAPIAdapterTests {
    @Test("Source Calendars paginate and exclude hidden or unreadable entries")
    func paginatedFilteredSourceCalendars() async {
        let transport = CalendarListTransport()
        let adapter = GoogleCalendarAPIAdapter(
            accessTokenProvider: { "test-token" },
            loadRequest: { request in
                try await transport.load(request)
            }
        )

        let outcome = await adapter.fetchSourceCalendars()

        #expect(
            outcome == .success([
                GoogleSourceCalendar(
                    id: "primary",
                    summary: "Personal",
                    backgroundColorHex: "#039BE5",
                    isPrimary: true
                ),
                GoogleSourceCalendar(
                    id: "team",
                    summary: "Team",
                    backgroundColorHex: "#7CB342",
                    isPrimary: false
                ),
                GoogleSourceCalendar(
                    id: "write",
                    summary: "Write",
                    backgroundColorHex: "#039BE5",
                    isPrimary: false
                ),
            ])
        )

        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(
            requests.allSatisfy {
                $0.url?.path == "/calendar/v3/users/me/calendarList"
                    && $0.value(forHTTPHeaderField: "Authorization")
                        == "Bearer test-token"
            }
        )
        #expect(
            URLComponents(
                url: requests[0].url!,
                resolvingAgainstBaseURL: false
            )?.queryItems?.contains(
                URLQueryItem(name: "maxResults", value: "250")
            ) == true
        )
        #expect(
            URLComponents(
                url: requests[1].url!,
                resolvingAgainstBaseURL: false
            )?.queryItems?.contains(
                URLQueryItem(name: "pageToken", value: "page-two")
            ) == true
        )
    }
}
