//
//  StubURLProtocol.swift
//  InspiRailTests
//

import Foundation

/// Answers every request made through a session built from `configuration()`,
/// and records it, so a test can count requests and read their headers.
/// Nothing reaches the network (#15).
///
/// Its state is shared by every session that uses it, so only the serialized
/// "Station store" suite uses it.
final class StubURLProtocol: URLProtocol {
    struct Reply {
        let status: Int
        let body: Data

        /// HTTP 200 with the six stations of `stationFixture`.
        static let stations = Reply(status: 200, body: Data(stationFixture.utf8))

        /// That status, with an empty JSON object as the body.
        static func status(_ code: Int) -> Reply {
            Reply(status: code, body: Data("{}".utf8))
        }
    }

    private struct State {
        var replies: [Reply] = [.stations]
        var requests: [URLRequest] = []
        var isHolding = false
        var held: [() -> Void] = []
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var state = State()

    /// An ephemeral configuration whose only protocol class is this stub.
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }

    /// Forgets the requests seen so far and answers the next ones with
    /// `replies`, in order. The last reply repeats.
    static func reset(replies: [Reply] = [.stations]) {
        lock.withLock { state = State(replies: replies) }
    }

    /// The requests answered or held so far, oldest first.
    static var requests: [URLRequest] {
        lock.withLock { state.requests }
    }

    /// Keeps every answer until `release()`.
    static func hold() {
        lock.withLock { state.isHolding = true }
    }

    /// Sends the answers held so far, and stops holding.
    static func release() {
        let held = lock.withLock {
            let held = state.held
            state.held = []
            state.isHolding = false
            return held
        }
        held.forEach { $0() }
    }

    /// Returns once `count` requests have arrived, or after five seconds.
    static func waitForRequests(_ count: Int) async {
        for _ in 0..<500 where requests.count < count {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // The client is called on the run loop that started the load.
        let runLoop = CFRunLoopGetCurrent()
        let (reply, isHolding) = Self.lock.withLock {
            Self.state.requests.append(request)
            let reply = Self.state.replies.count > 1 ? Self.state.replies.removeFirst() : Self.state.replies[0]
            return (reply, Self.state.isHolding)
        }
        let answer = {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                self.respond(with: reply)
            }
            CFRunLoopWakeUp(runLoop)
        }
        if isHolding {
            Self.lock.withLock { Self.state.held.append(answer) }
        } else {
            answer()
        }
    }

    override func stopLoading() {}

    private func respond(with reply: Reply) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// Six stations in the NS stations (v3) shape: four Dutch ones, not in name
/// order, one with an apostrophe, and two from other countries.
let stationFixture = """
{"payload":[
{"id":{"code":"UT","uicCode":"8400621"},"stationType":"MEGA_STATION","names":{"long":"Utrecht Centraal","medium":"Utrecht C.","short":"Utrecht C"},"location":{"lat":52.08901,"lng":5.110268},"country":"NL"},
{"id":{"code":"ASD","uicCode":"8400058"},"stationType":"MEGA_STATION","names":{"long":"Amsterdam Centraal","medium":"Amsterdam C.","short":"Amsterdm C"},"location":{"lat":52.37888,"lng":4.900277},"country":"NL"},
{"id":{"code":"HT","uicCode":"8400319"},"stationType":"KNOOPPUNT_INTERCITY_STATION","names":{"long":"'s-Hertogenbosch","medium":"'s-Hertogenb.","short":"Den Bosch"},"location":{"lat":51.69048,"lng":5.29362},"country":"NL"},
{"id":{"code":"ZL","uicCode":"8400747"},"stationType":"KNOOPPUNT_INTERCITY_STATION","names":{"long":"Zwolle","medium":"Zwolle","short":"Zwolle"},"location":{"lat":52.50474,"lng":6.091102},"country":"NL"},
{"id":{"code":"BHF","uicCode":"8011160"},"stationType":"MEGA_STATION","names":{"long":"Berlin Hbf","medium":"Berlin Hbf","short":"Berlin Hbf"},"location":{"lat":52.52508,"lng":13.369402},"country":"D"},
{"id":{"code":"BRUZ","uicCode":"8814001"},"stationType":"MEGA_STATION","names":{"long":"Brussel-Zuid","medium":"Brussel-Zuid","short":"Brussel Z"},"location":{"lat":50.83588,"lng":4.33645},"country":"B"}
]}
"""
