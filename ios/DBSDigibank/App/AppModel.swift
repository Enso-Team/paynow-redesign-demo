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
    private(set) var stage: LoadingStage?

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

    var flow: FlowMode { ABSettings.flow }

    func runStarted() {
        home.clear()
        TraceRecorder.shared.begin(flow: flow, multiplier: ABSettings.multiplier)
    }

    func attest() async throws -> String { try await session.attest() }

    func startSession(_ auth: AuthContext, attestation: String, challenged: (@MainActor @Sendable () -> Void)?) async throws {
        try await session.start(auth, attestation: attestation, challenged: challenged)
    }

    func loadHome() async throws {
        await home.refresh()
        if home.refreshFailed { throw APIError.transport("Couldn't load your accounts") }
    }

    func prefetchHome() { Task { await home.refresh() } }

    func leaveScanner() async {
        let span = TraceRecorder.shared.start("Scanner closes", .ui)
        await withCheckedContinuation { continuation in
            dismissWaiter = continuation
            journey = nil
        }
        TraceRecorder.shared.end(span)
    }

    func journeyDismissed() {
        let waiter = dismissWaiter
        dismissWaiter = nil
        waiter?.resume()
    }

    func showStage(_ stage: LoadingStage) { setStage(stage) }

    private func setStage(_ next: LoadingStage?) {
        TraceRecorder.shared.end(stageToken)
        stageToken = next.flatMap { TraceRecorder.shared.startScreen($0.rawValue) }
        stage = next
    }

    func bootShell() async {
        let span = TraceRecorder.shared.start("Signed-in app mounts", .ui)
        await withCheckedContinuation { continuation in
            homeWaiter = continuation
            selectedTab = .home
            phase = .signedIn
        }
        TraceRecorder.shared.end(span)
    }

    func homeAppeared() {
        let waiter = homeWaiter
        homeWaiter = nil
        waiter?.resume()
    }

    func revealHome() async {
        let span = TraceRecorder.shared.start("Home appears", .ui)
        await withCheckedContinuation { continuation in
            withAnimation(.easeInOut(duration: 0.25)) { setStage(nil) } completion: { continuation.resume() }
        }
        TraceRecorder.shared.end(span)
        selectedTab = .pay
    }

    /// The form's first call means its page is up.
    func formMounted() {
        TraceRecorder.shared.end(Self.formSpan)
        if stage == .paySkeleton { setStage(nil) }
    }

    func abandon() {
        if stage != nil {
            setStage(nil)
            phase = .signedOut
        }
        guard TraceRecorder.shared.isRunning else { return }
        TraceRecorder.shared.cancel()
        journey = nil
    }

    // MARK: Run spans that cross views

    static let scannerSpan = "Scanner opens"
    static let scanSpan = "Aim and scan"
    static let formSpan = "PayNow form opens"
    static let sentSpan = "Sent screen opens"

    @ObservationIgnored private var dismissWaiter: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var stageToken: TraceRecorder.Token?
    @ObservationIgnored private var homeWaiter: CheckedContinuation<Void, Never>?

    func scannerAppeared() {
        TraceRecorder.shared.end(Self.scannerSpan)
        if journey?.path.isEmpty == true { _ = TraceRecorder.shared.start(Self.scanSpan, .user) }
    }

    func sentAppeared(_ result: PaymentResult) {
        TraceRecorder.shared.end(Self.sentSpan)
        guard let trace = TraceRecorder.shared.finish(), result.settled,
              let body = try? JSONEncoder().encode(trace) else { return }
        Task {
            let request = APIRequest(service: .auth, path: "/auth/traces", method: "POST", body: body)
            let response = try? await session.send(request, interactive: false)
            if response?.status != 201 { report("Couldn't save this run's trace") }
        }
    }

    private func traceLanding(_ destination: Destination) {
        switch destination {
        case .scanner: _ = TraceRecorder.shared.start(Self.scannerSpan, .ui)
        case .form:
            _ = TraceRecorder.shared.start(Self.formSpan, .ui)
            if phase == .signedIn, flow == .sequential, TraceRecorder.shared.isRunning { setStage(.paySkeleton) }
        default: break
        }
    }

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
            traceLanding(destination)
            journey = Journey(root: destination)
        case .push(let destination):
            traceLanding(destination)
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
        _ = TraceRecorder.shared.start(Self.sentSpan, .ui)
        journey?.path.append(.sent(result))
        Task { await home.refresh() }
    }

    /// The form's close(): back one screen, or out of the journey.
    func closeForm() {
        setStage(nil)
        TraceRecorder.shared.cancel()
        guard let current = journey else { return }
        if current.path.isEmpty { journey = nil } else { journey?.path.removeLast() }
    }

    func endJourney() {
        setStage(nil)
        TraceRecorder.shared.cancel()
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
        setStage(nil)
        TraceRecorder.shared.cancel()
        journey = nil
        if phase == .signedIn { phase = .signedOut }
        home.clear()
        report("You've been logged out")
    }

    private func deviceForgotten() {
        setStage(nil)
        TraceRecorder.shared.cancel()
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
