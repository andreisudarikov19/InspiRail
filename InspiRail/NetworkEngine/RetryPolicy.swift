//
//  RetryPolicy.swift
//  InspiRail
//
//  Which failed requests are tried again, and after how long
//

import Foundation

/// Which failed requests to the NS API are tried again, and how long to wait
/// before the next attempt (#20).
nonisolated enum RetryPolicy {
    /// Whether a transport failure is worth another attempt: it fails fast,
    /// and often passes on a second try. No internet and a timeout come after
    /// the session has already waited, and a TLS failure doesn't pass in
    /// seconds, so they aren't retried.
    static func isTransient(_ code: URLError.Code) -> Bool {
        switch code {
        case .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }
    
    /// The wait a `Retry-After` header asks for: whole seconds, or an HTTP
    /// date in any of the three forms HTTP allows. Never negative: 0, a
    /// negative number or a date in the past asks no wait. A number too large
    /// for an `Int` is longer than any wait. Nil when the header is missing
    /// or can't be read.
    static func retryAfter(_ value: String?, now: Date) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return nil
        }
        if let seconds = Int(value) {
            return TimeInterval(max(0, seconds))
        }
        if value.allSatisfy({ $0.isASCII && $0.isNumber }) {
            return TimeInterval(value) ?? .infinity
        }
        guard let date = httpDate(value, now: now) else {
            return nil
        }
        return max(0, date.timeIntervalSince(now))
    }
    
    /// An HTTP date in any of its three forms (RFC 9110, section 5.6.7), read
    /// without regard to case: IMF-fixdate (`Mon, 01 Jan 2001 00:00:07 GMT`),
    /// RFC 850 (`Monday, 01-Jan-01 00:00:07 GMT`) and asctime
    /// (`Mon Jan  1 00:00:07 2001`). A two-digit year is never read as more
    /// than 50 years ahead of `now`, as HTTP asks.
    private static func httpDate(_ value: String, now: Date) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = formatter.timeZone
        formatter.twoDigitStartDate = calendar.date(byAdding: .year, value: -50, to: now)
        // Day and month names are read in any case, but "GMT" only in
        // capitals.
        let value = value.uppercased()
        for format in ["EEE, dd MMM yyyy HH:mm:ss 'GMT'", "EEEE, dd-MMM-yy HH:mm:ss 'GMT'", "EEE MMM d HH:mm:ss yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
    
    /// The wait after attempt `attempt` when the server names none: 1 s,
    /// then 2 s.
    static func backoff(afterAttempt attempt: Int) -> TimeInterval {
        pow(2, Double(attempt - 1))
    }
}
