import Foundation
import Testing
@testable import digibank

/// Scripted auth and data services.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _log: [String] = []
    private var _dataStatuses: [Int] = []
    private var issued = 0

    var log: [String] { lock.withLock { _log } }

    func queueDataStatuses(_ statuses: [Int]) { lock.withLock { _dataStatuses = statuses } }

    func perform(_ request: URLRequest) async throws -> APIResponse {
        let path = request.url?.path ?? ""
        return lock.withLock {
            _log.append(path)
            switch path {
            case "/auth/attest":
                return Self.json(200, ["attestationId": "att-\(_log.count)"])
            case "/auth/challenge":
                return Self.json(200, ["nonce": "n-\(_log.count)", "expiresAt": "2099-01-01T00:00:00Z"])
            case "/auth/session", "/auth/refresh":
                issued += 1
                return Self.json(200, ["accessToken": "access-\(issued)", "refreshToken": "refresh-\(issued)",
                                       "expiresAt": Date().addingTimeInterval(300).timeIntervalSince1970])
            default:
                let status = _dataStatuses.isEmpty ? 200 : _dataStatuses.removeFirst()
                let auth = request.value(forHTTPHeaderField: "Authorization") ?? ""
                return Self.json(status, ["auth": auth])
            }
        }
    }

    static func json(_ status: Int, _ body: [String: Any]) -> APIResponse {
        APIResponse(status: status, data: try! JSONSerialization.data(withJSONObject: body), headers: [:])
    }
}

final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now = Date()
    var now: Date { lock.withLock { _now } }
    func advance(_ seconds: TimeInterval) { lock.withLock { _now += seconds } }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.withLock { _value } }
    func increment() { lock.withLock { _value += 1 } }
}

@Suite("SessionManager")
struct SessionManagerTests {
    let transport = FakeTransport()
    let clock = Clock()
    let faceIDCount = Counter()
    let signOuts = Counter()

    func makeSession(faceIDPasses: Bool = true) async -> SessionManager {
        let clock = clock
        let session = SessionManager(transport: transport, deviceId: { "device-1" },
                                     sign: { _, _ in Data([1, 2, 3]) }, now: { clock.now })
        let faceIDCount = faceIDCount
        let signOuts = signOuts
        await session.setHooks(.init(
            reauthenticate: { faceIDCount.increment(); return faceIDPasses ? AuthContext(nil) : nil },
            signedOut: { signOuts.increment() },
            deviceUnknown: {}
        ))
        return session
    }

    @Test func startSwapsTheSignedNonceForASession() async throws {
        let session = await makeSession()
        try await session.start(AuthContext(nil))
        #expect(transport.log == ["/auth/attest", "/auth/challenge", "/auth/session"])
        #expect(await session.isLive)
    }

    @Test func callsCarryTheBearerToken() async throws {
        let session = await makeSession()
        try await session.start(AuthContext(nil))
        let response = try await session.send(APIRequest(service: .account, path: "/accounts/summary"))
        let body = try JSONSerialization.jsonObject(with: response.data) as? [String: String]
        #expect(body?["auth"] == "Bearer access-1")
        #expect(faceIDCount.value == 0)
    }

    @Test func idleForFiveMinutesAsksFaceIDOnceAndCarriesOn() async throws {
        let session = await makeSession()
        try await session.start(AuthContext(nil))
        clock.advance(SessionManager.idleTimeout + 1)
        #expect(await session.isLive == false)
        let response = try await session.send(APIRequest(service: .lookup, path: "/paynow/lookup?type=MOBILE&value=91234567"))
        #expect(response.status == 200)
        #expect(faceIDCount.value == 1)
    }

    @Test func backgroundCallsNeverShowFaceID() async throws {
        let session = await makeSession()
        try await session.start(AuthContext(nil))
        clock.advance(SessionManager.idleTimeout + 1)
        await #expect(throws: SessionError.needsFaceID) {
            try await session.send(APIRequest(service: .account, path: "/accounts/summary"), interactive: false)
        }
        #expect(faceIDCount.value == 0)
    }

    @Test func expiredAccessTokenRefreshesQuietly() async throws {
        let session = await makeSession()
        try await session.start(AuthContext(nil))
        clock.advance(200)
        _ = try await session.send(APIRequest(service: .account, path: "/accounts/summary"))
        clock.advance(200)
        _ = try await session.send(APIRequest(service: .account, path: "/accounts/summary"))
        #expect(transport.log.contains("/auth/refresh"))
        #expect(faceIDCount.value == 0)
    }

    @Test func a401TriggersOneFaceIDRecheckThenRetries() async throws {
        let session = await makeSession()
        try await session.start(AuthContext(nil))
        transport.queueDataStatuses([401, 200])
        let response = try await session.send(APIRequest(service: .payment, path: "/payments/p1"))
        #expect(response.status == 200)
        #expect(faceIDCount.value == 1)
        #expect(signOuts.value == 0)
    }

    @Test func aSecond401SignsOut() async throws {
        let session = await makeSession()
        try await session.start(AuthContext(nil))
        transport.queueDataStatuses([401, 401])
        await #expect(throws: SessionError.signedOut) {
            try await session.send(APIRequest(service: .payment, path: "/payments/p1"))
        }
        #expect(faceIDCount.value == 1)
        #expect(signOuts.value == 1)
        #expect(await session.isLive == false)
    }

    @Test func cancelledRecheckSignsOut() async throws {
        let session = await makeSession(faceIDPasses: false)
        try await session.start(AuthContext(nil))
        clock.advance(SessionManager.idleTimeout + 1)
        await #expect(throws: SessionError.cancelled) {
            try await session.send(APIRequest(service: .account, path: "/accounts/summary"))
        }
        #expect(signOuts.value == 1)
    }

    /// Run 8: the form's lookup was the last API call, then 5 min 55 s passed before Pay.
    /// With nothing else resetting the idle clock, Pay ran the idle re-check.
    @Test func run8NoTouchesForSixMinutesMakesPayAskAgain() async throws {
        let session = await makeSession()
        try await session.start(AuthContext(nil))
        _ = try await session.send(APIRequest(service: .lookup, path: "/paynow/lookup?type=MOBILE&value=91234567"))
        clock.advance(355)
        _ = try await session.send(APIRequest(service: .payment, path: "/payments/paynow", method: "POST"))
        #expect(faceIDCount.value == 1)
    }

    /// Typing and tapping in the journey reset the idle clock, so Pay never asks.
    @Test func touchesDuringTheJourneyKeepPayFromAsking() async throws {
        let session = await makeSession()
        try await session.start(AuthContext(nil))
        _ = try await session.send(APIRequest(service: .lookup, path: "/paynow/lookup?type=MOBILE&value=91234567"))
        for _ in 0..<4 {
            clock.advance(90)
            await session.touch()
        }
        clock.advance(30)
        _ = try await session.send(APIRequest(service: .payment, path: "/payments/paynow", method: "POST"))
        #expect(faceIDCount.value == 0)
        #expect(transport.log.contains("/auth/refresh"))
    }

    /// An older session went idle. The entry Face ID starts a fresh session, so Pay doesn't ask.
    @Test func entryFaceIDAfterAnOldIdleSessionStartsFreshAndPayNeverAsks() async throws {
        let session = await makeSession()
        try await session.start(AuthContext(nil))
        clock.advance(SessionManager.idleTimeout + 60)
        #expect(await session.isLive == false)
        try await session.start(AuthContext(nil))
        #expect(transport.log.filter { $0 == "/auth/challenge" }.count == 2)
        clock.advance(60)
        _ = try await session.send(APIRequest(service: .payment, path: "/payments/paynow", method: "POST"))
        #expect(faceIDCount.value == 0)
    }

    @Test func jwtExpiryIsReadFromTheExpClaim() {
        let payload = Data(#"{"sub":"u1","exp":4102444800}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        #expect(JWT.expiry("h.\(payload).s") == Date(timeIntervalSince1970: 4_102_444_800))
    }
}
