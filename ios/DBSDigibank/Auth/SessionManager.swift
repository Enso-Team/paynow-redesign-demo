import Foundation
import LocalAuthentication

/// An evaluated LAContext, handed to the Keychain so signing doesn't prompt twice.
/// `nil` when the mocked Face ID sheet ran.
final class AuthContext: @unchecked Sendable {
    let laContext: LAContext?
    init(_ laContext: LAContext?) { self.laContext = laContext }
}

enum SessionError: Error, Equatable, LocalizedError {
    case cancelled
    case signedOut
    case deviceUnknown
    case needsFaceID
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: "Face ID was cancelled"
        case .signedOut: "You've been logged out"
        case .deviceUnknown: "This iPhone needs to be set up again"
        case .needsFaceID: "Face ID needed"
        case .failed(let message): message
        }
    }
}

/// Owns the session token for the whole app.
/// - Access JWT 5 min, refresh token 30 min (rolling).
/// - Idle 5 min since the last touch: the next interactive call asks Face ID once more and carries on.
/// - A 401 triggers the same re-check once. A second 401 signs the user out.
actor SessionManager {
    struct Tokens: Sendable {
        var access: String
        var refresh: String
        var accessExpiry: Date
    }

    struct Hooks: Sendable {
        /// Runs the Face ID re-check. Returns nil when cancelled.
        var reauthenticate: @Sendable () async -> AuthContext?
        var signedOut: @Sendable () async -> Void
        var deviceUnknown: @Sendable () async -> Void
    }

    static let idleTimeout: TimeInterval = 5 * 60

    private let transport: HTTPTransport
    private let deviceId: @Sendable () -> String?
    private let sign: @Sendable (Data, AuthContext?) throws -> Data
    private let now: @Sendable () -> Date
    private var hooks: Hooks?

    private var tokens: Tokens?
    private var lastTouch: Date = .distantPast
    private var recheckTask: Task<Void, Error>?

    init(
        transport: HTTPTransport = URLSessionTransport(),
        deviceId: @escaping @Sendable () -> String? = { DeviceBinding.current?.deviceId },
        sign: @escaping @Sendable (Data, AuthContext?) throws -> Data = { try DeviceKey.full.sign($0, context: $1?.laContext) },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.transport = transport
        self.deviceId = deviceId
        self.sign = sign
        self.now = now
    }

    func setHooks(_ hooks: Hooks) { self.hooks = hooks }

    var isLive: Bool { tokens != nil && !idleExpired }

    func touch() { if tokens != nil { lastTouch = now() } }

    func end() {
        tokens = nil
        lastTouch = .distantPast
    }

    private var idleExpired: Bool { now().timeIntervalSince(lastTouch) > Self.idleTimeout }

    // MARK: Session setup

    /// Swaps the Face ID-unlocked device key for a session: challenge, sign the nonce, session.
    func start(_ auth: AuthContext?) async throws {
        guard let deviceId = deviceId() else { throw SessionError.deviceUnknown }
        let api = PublicAPI(transport: transport)

        let challenge = try await api.post(.auth, "/auth/challenge", ["deviceId": deviceId])
        if challenge.errorCode == "DEVICE_UNKNOWN" { try await deviceIsUnknown() }
        guard challenge.status == 200 || challenge.status == 201,
              let nonce = try? challenge.decode(Challenge.self).nonce
        else { throw SessionError.failed("Challenge failed (\(challenge.status))") }

        let signature = try sign(Data(nonce.utf8), auth).base64EncodedString()
        let session = try await api.post(.auth, "/auth/session",
                                         ["deviceId": deviceId, "nonce": nonce, "signature": signature])
        if session.errorCode == "DEVICE_UNKNOWN" { try await deviceIsUnknown() }
        guard session.status == 200 || session.status == 201 else {
            throw SessionError.failed("Session failed (\(session.errorCode ?? "\(session.status)"))")
        }
        try store(session)
    }

    private func deviceIsUnknown() async throws -> Never {
        end()
        await hooks?.deviceUnknown()
        throw SessionError.deviceUnknown
    }

    private func store(_ response: APIResponse) throws {
        let body = try response.decode(TokenResponse.self)
        tokens = Tokens(access: body.accessToken, refresh: body.refreshToken,
                        accessExpiry: body.expiry(fallback: now().addingTimeInterval(300)))
        lastTouch = now()
    }

    private func refresh() async throws {
        guard let refreshToken = tokens?.refresh else { throw SessionError.needsFaceID }
        let response = try await PublicAPI(transport: transport).post(.auth, "/auth/refresh", ["refreshToken": refreshToken])
        guard response.status == 200 || response.status == 201 else { throw SessionError.needsFaceID }
        let touched = lastTouch
        try store(response)
        lastTouch = touched
    }

    /// The one Face ID re-check, shared by every caller waiting on it.
    private func recheck() async throws {
        if let recheckTask { return try await recheckTask.value }
        let task = Task { [hooks] in
            guard let auth = await hooks?.reauthenticate() else { throw SessionError.cancelled }
            try await self.start(auth)
        }
        recheckTask = task
        defer { recheckTask = nil }
        do {
            try await task.value
        } catch {
            if error as? SessionError != .deviceUnknown { await signOut() }
            throw error
        }
    }

    private func signOut() async {
        end()
        await hooks?.signedOut()
    }

    // MARK: Authorised calls

    /// A token that's good to use now. Interactive calls may run the Face ID re-check.
    func accessToken(interactive: Bool) async throws -> String {
        if let recheckTask { try await recheckTask.value }
        if tokens == nil || idleExpired {
            guard interactive else { throw SessionError.needsFaceID }
            try await recheck()
        } else if let tokens, tokens.accessExpiry.timeIntervalSince(now()) < 15 {
            do {
                try await refresh()
            } catch {
                guard interactive else { throw SessionError.needsFaceID }
                try await recheck()
            }
        }
        guard let access = tokens?.access else { throw SessionError.needsFaceID }
        return access
    }

    /// Sends a call with the Bearer token. Background (non-interactive) calls never show Face ID.
    func send(_ request: APIRequest, interactive: Bool = true) async throws -> APIResponse {
        let token = try await accessToken(interactive: interactive)
        if interactive { lastTouch = now() }
        let first = try await transport.perform(request.urlRequest(bearer: token))
        guard first.status == 401 else { return first }
        guard interactive else { throw SessionError.needsFaceID }

        try await recheck()
        let retry = try await transport.perform(request.urlRequest(bearer: tokens?.access))
        if retry.status == 401 {
            await signOut()
            throw SessionError.signedOut
        }
        return retry
    }
}

private struct Challenge: Decodable {
    var nonce: String
}

private struct TokenResponse: Decodable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: ExpiresAt?

    enum ExpiresAt: Decodable {
        case number(Double)
        case text(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Double.self) { self = .number(number) } else {
                self = .text(try container.decode(String.self))
            }
        }

        var date: Date? {
            switch self {
            case .number(let value):
                Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
            case .text(let value):
                (try? Date(value, strategy: .iso8601))
                    ?? ISO8601DateFormatter.fractional.date(from: value)
                    ?? Double(value).map { Date(timeIntervalSince1970: $0 > 10_000_000_000 ? $0 / 1000 : $0) }
            }
        }
    }

    func expiry(fallback: Date) -> Date {
        expiresAt?.date ?? JWT.expiry(accessToken) ?? fallback
    }
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

enum JWT {
    static func expiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = claims["exp"] as? Double
        else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
