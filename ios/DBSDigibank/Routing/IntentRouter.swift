import Foundation
import SGQR

/// What the user tapped.
enum Intent: Equatable, Sendable {
    case login
    case scanAndPay
    case payNow
    case payQR(String)
    case overseas
    case apply

    /// The journey name Face ID shows.
    var journeyName: String {
        switch self {
        case .login: "Log in"
        case .scanAndPay: "Scan & Pay"
        case .payNow, .payQR: "PayNow"
        case .overseas: "Overseas Transfer"
        case .apply: "Apply"
        }
    }

    /// Journeys that need your data ask Face ID first. Overseas asks at Send and Apply when an
    /// application starts, both outside this demo.
    var needsSession: Bool {
        switch self {
        case .login, .scanAndPay, .payNow, .payQR: true
        case .overseas, .apply: false
        }
    }
}

/// Where a tap came from. Taps on the signed-out entry screen start a new journey and always ask
/// Face ID. Taps inside the app reuse the live session and ask only after idle time.
enum Origin: Equatable, Sendable {
    case entry
    case shell
    case journey
}

/// Screens a journey can show.
enum Destination: Hashable, Sendable {
    case scanner
    case paynowMenu
    case form(PaynowInit)
    case sent(PaymentResult)
    case placeholder(String)
}

enum Landing: Equatable, Sendable {
    case home
    case applyTab
    case journey(Destination)
    case push(Destination)
}

@MainActor
protocol RouterEnvironment: AnyObject {
    func faceID(_ journey: String) async -> AuthContext?
    var flow: FlowMode { get }
    func runStarted()
    func attest() async throws -> String
    func startSession(_ auth: AuthContext, attestation: String, challenged: (@MainActor @Sendable () -> Void)?) async throws
    /// Closes the scanner and returns once it is gone.
    func leaveScanner() async
    func showStage(_ stage: LoadingStage)
    /// Mounts the signed-in half of the app under the splash.
    func bootShell() async
    /// Fetches the account summary, and throws when it fails.
    func loadHome() async throws
    func prefetchHome()
    /// Fades the loading screen out and returns once Home is on screen.
    func revealHome() async
    /// Drops the journey and any run under way.
    func abandon()
    func sessionIsLive() async -> Bool
    func touchSession() async
    func land(_ landing: Landing)
    func report(_ message: String)
}

/// Holds the one pending intent and takes the user straight to it, through Face ID when needed.
/// When Face ID is cancelled the intent is dropped and the user stays where they were.
@MainActor
@Observable
final class IntentRouter {
    private(set) var pending: Intent?
    /// DBS Sequential opened the scanner with no session, so the decoded QR runs the whole chain.
    private var scanFirst = false
    @ObservationIgnored weak var environment: RouterEnvironment?

    init(environment: RouterEnvironment? = nil) {
        self.environment = environment
    }

    func handle(_ intent: Intent, from origin: Origin) async {
        guard pending == nil, let environment else { return }
        pending = intent
        defer { pending = nil }

        if case .payQR = intent {} else { scanFirst = false }
        if intent == .scanAndPay, origin == .entry {
            environment.runStarted()
            if environment.flow == .sequential {
                scanFirst = true
                environment.land(.journey(.scanner))
                return
            }
        }

        var form: PaynowInit?
        if case .payQR(let raw) = intent {
            do {
                form = PaynowInit(qr: try SGQR.parse(raw))
            } catch {
                environment.report(error.localizedDescription)
                return
            }
        }

        if scanFirst, let form {
            scanFirst = false
            await runSequential(intent, form: form, environment)
            return
        }

        if intent.needsSession {
            let live = await environment.sessionIsLive()
            if origin == .entry || !live {
                // Attestation runs while Face ID is on screen.
                let attestation = Task { try await environment.attest() }
                guard let auth = await environment.faceID(intent.journeyName) else {
                    attestation.cancel()
                    environment.abandon()
                    return
                }
                do {
                    try await environment.startSession(auth, attestation: attestation.value, challenged: nil)
                } catch {
                    environment.report(error.localizedDescription)
                    environment.abandon()
                    return
                }
                if intent == .scanAndPay { environment.prefetchHome() }
            } else {
                await environment.touchSession()
            }
        }

        environment.land(Self.landing(for: intent, from: origin, form: form))
    }

    /// One call at a time, through Home, to the form. Which call each screen waits for is predicted from
    /// recordings of the real app, which show screens and not calls.
    private func runSequential(_ intent: Intent, form: PaynowInit, _ environment: RouterEnvironment) async {
        await environment.leaveScanner()
        do {
            environment.showStage(.entrySpinner)
            let attestation = try await environment.attest()
            environment.showStage(.splash)
            await environment.bootShell()
            guard let auth = await environment.faceID(intent.journeyName) else { return environment.abandon() }
            environment.showStage(.splashSpinner)
            try await environment.startSession(auth, attestation: attestation) { environment.showStage(.login) }
            environment.showStage(.homeSkeleton)
            try await environment.loadHome()
        } catch {
            environment.report(error.localizedDescription)
            return environment.abandon()
        }
        await environment.revealHome()
        environment.land(.journey(.form(form)))
    }

    static func landing(for intent: Intent, from origin: Origin, form: PaynowInit? = nil) -> Landing {
        switch intent {
        case .login: .home
        case .scanAndPay: .journey(.scanner)
        case .payNow: .journey(.paynowMenu)
        case .payQR(let raw):
            Self.formLanding(form ?? (try? SGQR.parse(raw)).map(PaynowInit.init(qr:)), origin: origin)
        case .overseas: .journey(.placeholder("Overseas Transfer"))
        case .apply: origin == .shell ? .applyTab : .journey(.placeholder("Apply & More Services"))
        }
    }

    private static func formLanding(_ form: PaynowInit?, origin: Origin) -> Landing {
        let destination = Destination.form(form ?? PaynowInit(amountEditable: true, source: "qr"))
        return origin == .journey ? .push(destination) : .journey(destination)
    }
}
