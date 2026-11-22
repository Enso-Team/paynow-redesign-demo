import Foundation
import Testing
@testable import digibank

/// Scripted auth and account services for Peek. Records each request's path and JSON body.
final class PeekTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [(path: String, body: [String: String])] = []
    private var _peekStatuses: [Int] = []
    private var passes = 0

    var paths: [String] { lock.withLock { _requests.map(\.path) } }
    var sessionBodies: [[String: String]] { lock.withLock { _requests.filter { $0.path == "/auth/session" }.map(\.body) } }

    func queuePeekStatuses(_ statuses: [Int]) { lock.withLock { _peekStatuses = statuses } }

    func perform(_ request: URLRequest) async throws -> APIResponse {
        let path = request.url?.path ?? ""
        let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] } ?? [:]
        return lock.withLock {
            _requests.append((path, body))
            switch path {
            case "/auth/challenge":
                return FakeTransport.json(200, ["nonce": "n-\(_requests.count)", "expiresAt": "2099-01-01T00:00:00Z"])
            case "/auth/session":
                passes += 1
                return FakeTransport.json(200, ["accessToken": "peek-\(passes)", "expiresAt": "2099-01-01T00:00:00Z"])
            default:
                let status = _peekStatuses.isEmpty ? 200 : _peekStatuses.removeFirst()
                return FakeTransport.json(status, [
                    "balance": "2,264.57", "currency": "SGD", "asOf": "2026-11-20T09:32:00.123Z",
                    "transactions": [["type": "PayNow Transfer", "date": "2026-11-20", "amount": "-12.50"]],
                ])
            }
        }
    }
}

final class SignLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _messages: [String] = []
    var messages: [String] { lock.withLock { _messages } }
    func append(_ message: String) { lock.withLock { _messages.append(message) } }
}

@MainActor
@Suite("PeekClient")
struct PeekClientTests {
    let transport = PeekTransport()
    let clock = Clock()
    let signed = SignLog()

    func client() -> PeekClient {
        PeekClient(transport: transport,
                   peekDeviceId: { "peek-device" },
                   sign: { [signed] message in
                       signed.append(String(decoding: message, as: UTF8.self))
                       return Data("sig".utf8)
                   },
                   now: { [clock] in clock.now })
    }

    @Test func firstLoadGetsAPeekPassThenTheBalance() async throws {
        let peek = client()
        let data = try await peek.load()
        #expect(data.balance == "2,264.57")
        #expect(transport.paths == ["/auth/challenge", "/auth/session", "/accounts/peek"])
    }

    @Test func aRepeatHoldWithinAMinuteIsServedFromTheCache() async throws {
        let peek = client()
        _ = try await peek.load()
        clock.advance(59)
        #expect(peek.cached?.balance == "2,264.57")
        _ = try await peek.load()
        #expect(transport.paths.count == 3)
    }

    @Test func theCacheExpiresAfterSixtySeconds() async throws {
        let peek = client()
        _ = try await peek.load()
        clock.advance(61)
        #expect(peek.cached == nil)
        _ = try await peek.load()
        #expect(transport.paths.filter { $0 == "/accounts/peek" }.count == 2)
    }

    @Test func overlappingHoldsShareOneRequest() async throws {
        let peek = client()
        async let first = peek.load()
        async let second = peek.load()
        _ = try await (first, second)
        #expect(transport.paths.filter { $0 == "/accounts/peek" }.count == 1)
    }

    @Test func a401GetsOneNewPass() async throws {
        transport.queuePeekStatuses([401, 200])
        let data = try await client().load()
        #expect(data.currency == "SGD")
        #expect(transport.sessionBodies.count == 2)
    }

    @Test func aSecond401Fails() async {
        transport.queuePeekStatuses([401, 401])
        await #expect(throws: PeekError.failed(401)) { try await client().load() }
        #expect(transport.sessionBodies.count == 2)
    }

    /// The Peek key has no biometry and the signer takes no LAContext, so no pass can raise Face ID.
    @Test func everyPassIsAPeekScopeSessionSignedWithThePeekKey() async throws {
        transport.queuePeekStatuses([401, 200])
        _ = try await client().load()
        for body in transport.sessionBodies {
            #expect(body["scope"] == "peek")
            #expect(body["deviceId"] == "peek-device")
        }
        #expect(signed.messages.count == 2)
        #expect(!DeviceKey.peek.biometry)
        #expect(DeviceKey.full.biometry)
    }

    @Test func formatsMatchTheWeb() {
        #expect(PeekFormat.day("2026-11-19") == "19 Nov")
        #expect(PeekFormat.signed("-12.50") == "-12.50")
        #expect(PeekFormat.signed("500") == "+500.00")
        #expect(PeekFormat.signed("1234.5") == "+1,234.50")
    }
}
