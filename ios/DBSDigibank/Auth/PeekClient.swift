import Foundation

struct PeekTransaction: Codable, Sendable, Hashable {
    var type: String
    var date: String
    var amount: String
}

/// `GET /accounts/peek`: the first deposit account's balance and its latest 3 transactions.
struct PeekBalance: Codable, Sendable, Equatable {
    var balance: String
    var currency: String
    var asOf: String
    var transactions: [PeekTransaction]
}

enum PeekError: Error, Equatable {
    case deviceUnknown
    case failed(Int)
}

/// Peek Balance data. It signs with the Peek key, which has no biometry, so it never asks Face ID.
/// - The read-only pass comes from `POST /auth/session` with `scope: "peek"` on the peek-only device.
/// - A 401 gets one new pass.
/// - The last result is kept for 60 s, so a repeat hold shows it on the first frame.
@MainActor
final class PeekClient {
    struct Pass: Sendable {
        var token: String
        var expiresAt: Date
    }

    static let cacheLifetime: TimeInterval = 60
    static let passMargin: TimeInterval = 5

    private let transport: HTTPTransport
    private let peekDeviceId: @Sendable () -> String?
    private let sign: @Sendable (Data) throws -> Data
    private let now: @Sendable () -> Date

    private var pass: Pass?
    private var stored: (data: PeekBalance, at: Date)?
    private var inflight: Task<PeekBalance, Error>?

    init(
        transport: HTTPTransport = URLSessionTransport(),
        peekDeviceId: @escaping @Sendable () -> String? = { DeviceBinding.current?.peekDeviceId },
        sign: @escaping @Sendable (Data) throws -> Data = { try DeviceKey.peek.sign($0, context: nil) },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.transport = transport
        self.peekDeviceId = peekDeviceId
        self.sign = sign
        self.now = now
    }

    /// The last result while it is under a minute old.
    var cached: PeekBalance? {
        guard let stored, now().timeIntervalSince(stored.at) < Self.cacheLifetime else { return nil }
        return stored.data
    }

    func load() async throws -> PeekBalance {
        if let cached { return cached }
        if let inflight { return try await inflight.value }
        let task = Task { try await fetch() }
        inflight = task
        defer { inflight = nil }
        return try await task.value
    }

    func reset() {
        pass = nil
        stored = nil
    }

    private func fetch() async throws -> PeekBalance {
        var response = try await get(token: try await token(renew: false))
        if response.status == 401 { response = try await get(token: try await token(renew: true)) }
        guard response.status == 200, let data = try? response.decode(PeekBalance.self) else {
            throw PeekError.failed(response.status)
        }
        stored = (data, now())
        return data
    }

    private func get(token: String) async throws -> APIResponse {
        let request = APIRequest(service: .account, path: "/accounts/peek")
        return try await transport.perform(request.urlRequest(bearer: token))
    }

    private func token(renew: Bool) async throws -> String {
        if !renew, let pass, pass.expiresAt.timeIntervalSince(now()) > Self.passMargin { return pass.token }
        let fresh = try await newPass()
        pass = fresh
        return fresh.token
    }

    private func newPass() async throws -> Pass {
        guard let deviceId = peekDeviceId() else { throw PeekError.deviceUnknown }
        let api = PublicAPI(transport: transport)
        let challenge = try await api.post(.auth, "/auth/challenge", ["deviceId": deviceId])
        if challenge.errorCode == "DEVICE_UNKNOWN" { throw PeekError.deviceUnknown }
        guard challenge.status == 200, let nonce = try? challenge.decode(PeekChallenge.self).nonce else {
            throw PeekError.failed(challenge.status)
        }
        let signature = try sign(Data(nonce.utf8)).base64EncodedString()
        let session = try await api.post(.auth, "/auth/session",
                                         ["deviceId": deviceId, "nonce": nonce, "signature": signature, "scope": "peek"])
        if session.errorCode == "DEVICE_UNKNOWN" { throw PeekError.deviceUnknown }
        guard session.status == 200, let body = try? session.decode(PassResponse.self) else {
            throw PeekError.failed(session.status)
        }
        let expiry = body.expiresAt.flatMap(Self.date) ?? JWT.expiry(body.accessToken) ?? now().addingTimeInterval(30)
        return Pass(token: body.accessToken, expiresAt: expiry)
    }

    private static func date(_ text: String) -> Date? {
        (try? Date(text, strategy: .iso8601)) ?? ISO8601DateFormatter.fractional.date(from: text)
    }
}

private struct PeekChallenge: Decodable {
    var nonce: String
}

private struct PassResponse: Decodable {
    var accessToken: String
    var expiresAt: String?
}

/// Peek's display text.
enum PeekFormat {
    private static let sg = Locale(identifier: "en_SG")

    /// "20 Nov 2026, 5:32 PM"
    static func asOf(_ iso: String) -> String {
        guard let date = (try? Date(iso, strategy: .iso8601)) ?? ISO8601DateFormatter.fractional.date(from: iso) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d MMM yyyy, h:mm a"
        return formatter.string(from: date)
    }

    /// "2026-11-19" → "19 Nov"
    static func day(_ date: String) -> String {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]) else { return date }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(parts[2]) \(months[parts[1] - 1])"
    }

    /// "-12.50" → "-12.50", "500" → "+500.00", with thousands separators.
    static func signed(_ amount: String) -> String {
        guard let value = Decimal(string: amount) else { return amount }
        let magnitude = Money.format(value < 0 ? -value : value)
        return (value < 0 ? "-" : "+") + magnitude
    }
}
