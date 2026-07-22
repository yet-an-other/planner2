import Foundation

/// One segment of the Event Detail Popover's plain-text Notes: ordinary
/// text or a whole http(s) URL whose string is both its visible label and
/// destination. The notes data model stays plain text; linkification is
/// presentation-only (iOS ADR 0005).
enum CalendarEventTextSegment: Equatable, Sendable {
    case text(String)
    case link(String)
}

/// Pure, presentation-only linkification for the Event Detail Popover's
/// plain-text Notes. Only http(s) URLs become links, so organizer text can
/// never introduce a script URL. Mirrors the Web Experience's text-links
/// seam while retaining iOS's deliberate case-insensitive scheme match.
enum CalendarEventTextLinks {
    static func splitIntoSegments(
        _ text: String
    ) -> [CalendarEventTextSegment] {
        var segments: [CalendarEventTextSegment] = []
        var cursor = text.startIndex

        while cursor < text.endIndex {
            guard
                let schemeRange = text.range(
                    of: "https?://",
                    options: [.regularExpression, .caseInsensitive],
                    range: cursor..<text.endIndex
                )
            else {
                segments.append(.text(String(text[cursor...])))
                break
            }

            if schemeRange.lowerBound > cursor {
                segments.append(
                    .text(String(text[cursor..<schemeRange.lowerBound]))
                )
            }

            // The URL runs to the first whitespace or bracketing
            // character, matching the Web Experience's generic URL
            // boundary.
            let terminators: Set<Character> = ["<", ">", "\"", "'", ")"]
            var end = schemeRange.upperBound
            while end < text.endIndex {
                let character = text[end]
                if character.isWhitespace || terminators.contains(character) {
                    break
                }
                end = text.index(after: end)
            }

            segments.append(
                .link(String(text[schemeRange.lowerBound..<end]))
            )
            cursor = end
        }

        return segments
    }
}

/// The Event Detail Popover's actionable location href: a place or address
/// as a Google Maps search, or a location that is itself an http(s) URL as
/// that direct URL. The location data model stays a plain string;
/// classification and href construction are presentation-only.
enum CalendarEventLocationHref: Equatable, Sendable {
    case maps(URL)
    case direct(URL)
}

/// Pure location linkification for the Event Detail Popover, symmetric
/// with `CalendarEventTextLinks` and the Web Experience's location-links
/// seam.
enum CalendarEventLocationLinks {
    static func href(for location: String) -> CalendarEventLocationHref? {
        if isWholeURL(location), let url = URL(string: location) {
            return .direct(url)
        }
        return mapsURL(for: location).map(CalendarEventLocationHref.maps)
    }

    /// Whether the whole location string is exactly one http(s) URL —
    /// deliberately excluding other schemes and URLs embedded in prose.
    private static func isWholeURL(_ location: String) -> Bool {
        let lowered = location.lowercased()
        guard lowered.hasPrefix("http://") || lowered.hasPrefix("https://")
        else {
            return false
        }
        return !location.contains(where: \.isWhitespace)
    }

    /// The documented Google Maps search URL for arbitrary free text,
    /// letting Maps geocode and interpret the place string. Whitespace
    /// collapses before encoding, matching the Web Experience.
    private static func mapsURL(for location: String) -> URL? {
        let collapsed = location
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard
            let query = collapsed.addingPercentEncoding(
                withAllowedCharacters: mapsQueryAllowed
            )
        else {
            return nil
        }
        return URL(
            string: "https://www.google.com/maps/search/?api=1&query=\(query)"
        )
    }

    /// The ASCII punctuation `encodeURIComponent` leaves unescaped. This
    /// keeps Maps hrefs aligned with the Web Experience and ensures query
    /// separators such as `&` and `=` remain data, never URL structure.
    private static let mapsQueryAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return allowed
    }()
}
