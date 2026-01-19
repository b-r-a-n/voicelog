import Foundation

enum DateParsing {
    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let plainDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Parse a date string with fallback support for various ISO8601 formats
    static func parseDate(_ dateString: String) -> Date? {
        // Try with fractional seconds and timezone
        if let date = iso8601WithFractionalSeconds.date(from: dateString) {
            return date
        }
        // Try without fractional seconds but with timezone
        if let date = iso8601Standard.date(from: dateString) {
            return date
        }
        // Try without timezone (backend sometimes returns dates without Z suffix)
        if let date = plainDateTime.date(from: dateString) {
            return date
        }
        return nil
    }

    /// Encode a date to ISO8601 format for sending to backend
    static func formatDate(_ date: Date) -> String {
        return iso8601Standard.string(from: date)
    }
}
