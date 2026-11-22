import SwiftUI
import UIKit

enum AppTab: Hashable {
    case home, pay, wealth, apply, more
}

/// A journey shown over the entry screen or the tab shell: scanner, PayNow menu, form, sent.
struct Journey: Identifiable {
    let id = UUID()
    var root: Destination
    var path: [Destination] = []
}

@MainActor
@Observable
final class AppModel: RouterEnvironment {
    enum Phase: Equatable { case setup, signedOut, signedIn }

    var phase: Phase
    var journey: Journey?
    var selectedTab: AppTab = .home
    var toast: String?

    let session = SessionManager()
    let faceID = FaceIDCheck()
    let router = IntentRouter()
    let peek = PeekClient()
    @ObservationIgnored lazy var home = HomeModel(session: session)

    init() {
        phase = DeviceBinding.current == nil ? .setup : .signedOut
        router.environment = self
        let session = session
        Task { [weak self] in
            await session.setHooks(.init(
                reauthenticate: { [weak self] in await self?.faceID.check("Continue") },
                signedOut: { [weak self] in await self?.sessionEnded() },
                deviceUnknown: { [weak self] in await self?.deviceForgotten() }
            ))
        }
    }

    @ObservationIgnored private var lastInteraction = Date.distantPast

    /// Any tap or keystroke, native or in the form, resets the session's idle clock (at most every 5 s).
    func userInteracted() {
        let now = Date.now
        guard now.timeIntervalSince(lastInteraction) >= 5 else { return }
        lastInteraction = now
        Task { await session.touch() }
    }

    func send(_ intent: Intent, from origin: Origin) {
        Task { await router.handle(intent, from: origin) }
    }

    // MARK: RouterEnvironment

    func faceID(_ journey: String) async -> AuthContext? { await faceID.check(journey) }

    func startSession(_ auth: AuthContext) async throws { try await session.start(auth) }

    func sessionIsLive() async -> Bool { await session.isLive }

    func touchSession() async { await session.touch() }

    func land(_ landing: Landing) {
        switch landing {
        case .home:
            journey = nil
            selectedTab = .home
            phase = .signedIn
            Task { await home.refresh() }
        case .applyTab:
            selectedTab = .apply
        case .journey(let destination):
            journey = Journey(root: destination)
        case .push(let destination):
            if journey == nil { journey = Journey(root: destination) } else { journey?.path.append(destination) }
        }
    }

    func report(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toast == message { toast = nil }
        }
    }

    // MARK: Journeys

    func paymentFinished(_ result: PaymentResult) {
        journey?.path.append(.sent(result))
        Task { await home.refresh() }
    }

    /// The form's close(): back one screen, or out of the journey.
    func closeForm() {
        guard let current = journey else { return }
        if current.path.isEmpty { journey = nil } else { journey?.path.removeLast() }
    }

    func endJourney() {
        journey = nil
        if phase == .signedIn { Task { await home.refresh() } }
    }

    // MARK: Device and session

    /// Registers the device key as a full device and the Peek key as a peek-only device.
    func bindDevice(username: String, otp: String) async throws {
        DeviceBinding.clear()
        peek.reset()
        do {
            let full = try await register(.full, scope: "full", username: username, otp: otp)
            let peekOnly = try await register(.peek, scope: "peek", username: username, otp: otp)
            DeviceBinding(deviceId: full.deviceId, peekDeviceId: peekOnly.deviceId, userId: full.userId).save()
        } catch {
            DeviceBinding.clear()
            throw error
        }
        phase = .signedOut
    }

    private func register(_ key: DeviceKey, scope: String, username: String, otp: String) async throws -> BindResponse {
        let body = [
            "username": username,
            "otp": otp,
            "deviceName": UIDevice.current.name,
            "publicKey": try key.create(),
            "scope": scope,
        ]
        let response = try await PublicAPI(transport: URLSessionTransport()).post(.auth, "/auth/devices", body)
        guard response.status == 201 || response.status == 200 else {
            if response.errorCode == "BAD_OTP" { throw SetupError.badOTP }
            throw SetupError.server(response.errorCode ?? "HTTP \(response.status)")
        }
        return try response.decode(BindResponse.self)
    }

    /// Peek's data for the entry screen. A forgotten device runs setup again.
    func loadPeek() async -> PeekBalance? {
        do {
            return try await peek.load()
        } catch PeekError.deviceUnknown {
            deviceForgotten()
            return nil
        } catch {
            return nil
        }
    }

    func logOut() {
        Task { await session.end() }
        journey = nil
        phase = .signedOut
        home.clear()
    }

    private func sessionEnded() {
        journey = nil
        if phase == .signedIn { phase = .signedOut }
        home.clear()
        report("You've been logged out")
    }

    private func deviceForgotten() {
        DeviceBinding.clear()
        peek.reset()
        journey = nil
        home.clear()
        phase = .setup
    }
}

enum SetupError: Error, LocalizedError {
    case badOTP
    case server(String)

    var errorDescription: String? {
        switch self {
        case .badOTP: "That OTP didn't match. Check it and try again."
        case .server(let code): "Couldn't set up this iPhone (\(code))."
        }
    }
}

private struct BindResponse: Decodable {
    var deviceId: String
    var userId: String

    enum CodingKeys: CodingKey { case deviceId, userId }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceId = try Self.stringOrNumber(container, .deviceId)
        userId = try Self.stringOrNumber(container, .userId)
    }

    private static func stringOrNumber(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> String {
        if let text = try? c.decode(String.self, forKey: key) { return text }
        return String(try c.decode(Int64.self, forKey: key))
    }
}
