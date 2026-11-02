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
    /// date (IMF-fixdate, such as `Mon, 01 Jan 2001 00:00:07 GMT`). Never
    /// negative. Nil when the header is missing or can't be read.
    static func retryAfter(_ value: String?, now: Date) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return nil
        }
        if let seconds = Int(value) {
            return TimeInterval(max(0, seconds))
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        guard let date = formatter.date(from: value) else {
            return nil
        }
        return max(0, date.timeIntervalSince(now))
    }

    /// The wait after attempt `attempt` when the server names none: 1 s,
    /// then 2 s.
    static func backoff(afterAttempt attempt: Int) -> TimeInterval {
        pow(2, Double(attempt - 1))
    }
}
