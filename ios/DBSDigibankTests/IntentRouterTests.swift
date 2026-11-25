import SGQR
import Testing
@testable import digibank

@MainActor
final class FakeEnvironment: RouterEnvironment {
    var faceIDPasses = true
    var live = false
    var faceIDPrompts: [String] = []
    var sessionsStarted = 0
    var landings: [Landing] = []
    var reports: [String] = []

    func faceID(_ journey: String) async -> AuthContext? {
        faceIDPrompts.append(journey)
        steps.append("faceID")
        return faceIDPasses ? AuthContext(nil) : nil
    }

    var flow = FlowMode.router
    var steps: [String] = []
    var homeFails = false

    func runStarted() { steps.append("run") }
    func attest() async throws -> String { steps.append("attest"); return "att" }
    func loadHome() async throws {
        steps.append("loadHome")
        if homeFails { throw SessionError.failed("summary") }
    }
    func prefetchHome() { steps.append("prefetchHome") }
    func leaveScanner() async { steps.append("leaveScanner") }
    func showStage(_ stage: LoadingStage) { steps.append(stage.rawValue) }
    func bootShell() async { steps.append("bootShell") }
    func revealHome() async { steps.append("revealHome") }
    func abandon() { steps.append("abandon") }

    func startSession(_ auth: AuthContext, attestation: String, challenged: (@MainActor @Sendable () -> Void)?) async throws {
        challenged?()
        steps.append("session")
        sessionsStarted += 1
        live = true
    }

    func sessionIsLive() async -> Bool { live }
    func touchSession() async {}
    func land(_ landing: Landing) { landings.append(landing) }
    func report(_ message: String) { reports.append(message) }
}

@MainActor
@Suite("IntentRouter")
struct IntentRouterTests {
    let env = FakeEnvironment()
    let router: IntentRouter

    init() {
        router = IntentRouter(environment: env)
    }

    @Test func loginAsksFaceIDNamedForTheJourneyThenLandsHome() async {
        await router.handle(.login, from: .entry)
        #expect(env.faceIDPrompts == ["Log in"])
        #expect(env.sessionsStarted == 1)
        #expect(env.landings == [.home])
        #expect(router.pending == nil)
    }

    @Test func scanAndPayAsksBeforeTheScanner() async {
        await router.handle(.scanAndPay, from: .entry)
        #expect(env.faceIDPrompts == ["Scan & Pay"])
        #expect(env.landings == [.journey(.scanner)])
    }

    @Test func payNowAsksBeforeTheMenu() async {
        await router.handle(.payNow, from: .entry)
        #expect(env.faceIDPrompts == ["PayNow"])
        #expect(env.landings == [.journey(.paynowMenu)])
    }

    @Test func cancelledFaceIDDropsTheIntentAndStaysPut() async {
        env.faceIDPasses = false
        await router.handle(.login, from: .entry)
        #expect(env.landings.isEmpty)
        #expect(env.sessionsStarted == 0)
        #expect(router.pending == nil)
    }

    @Test func entryTapsAlwaysAskEvenWithALiveSession() async {
        env.live = true
        await router.handle(.payNow, from: .entry)
        #expect(env.faceIDPrompts == ["PayNow"])
    }

    @Test func scanAndPayFromEntryAsksAgainAfterAFinishedJourney() async {
        await router.handle(.scanAndPay, from: .entry)
        #expect(env.live)
        await router.handle(.scanAndPay, from: .entry)
        #expect(env.faceIDPrompts == ["Scan & Pay", "Scan & Pay"])
        #expect(env.landings == [.journey(.scanner), .journey(.scanner)])
    }

    @Test func tapsInsideTheAppReuseTheLiveSession() async {
        env.live = true
        await router.handle(.scanAndPay, from: .shell)
        #expect(env.faceIDPrompts.isEmpty)
        #expect(env.landings == [.journey(.scanner)])
    }

    @Test func tapsInsideTheAppAskAgainAfterIdle() async {
        env.live = false
        await router.handle(.scanAndPay, from: .shell)
        #expect(env.faceIDPrompts == ["Scan & Pay"])
    }

    @Test func decodedQRPushesTheFormWithoutAnotherFaceID() async {
        env.live = true
        let raw = SGQR.encode(.init(proxyType: .mobile, proxyValue: "91234567", amount: "12.50", amountEditable: false))
        await router.handle(.payQR(raw), from: .journey)
        #expect(env.faceIDPrompts.isEmpty)
        let expected = PaynowInit(proxyType: "MOBILE", proxyValue: "91234567", amount: "12.50",
                                  amountEditable: false, source: "qr")
        #expect(env.landings == [.push(.form(expected))])
    }

    @Test func nonPayNowQRReportsAndGoesNowhere() async {
        env.live = true
        await router.handle(.payQR("hello"), from: .journey)
        #expect(env.landings.isEmpty)
        #expect(env.reports == ["This QR isn't a PayNow code"])
    }

    private var rawQR: String {
        SGQR.encode(.init(proxyType: .mobile, proxyValue: "91234567", amount: "12.50", amountEditable: false))
    }

    @Test func sequentialScansFirstThenRunsEveryStepInOrder() async {
        env.flow = .sequential
        env.live = true
        await router.handle(.scanAndPay, from: .entry)
        #expect(env.landings == [.journey(.scanner)])
        #expect(env.steps == ["run"])
        await router.handle(.payQR(rawQR), from: .journey)
        #expect(env.steps == ["run", "leaveScanner", "Entry grid spinner", "attest", "Splash", "bootShell", "faceID",
                              "Splash with spinner", "In-app login screen", "session", "Home skeleton", "loadHome", "revealHome"])
        #expect(env.landings.count == 2)
    }

    @Test func sequentialStopsWhenHomeFails() async {
        env.flow = .sequential
        env.homeFails = true
        await router.handle(.scanAndPay, from: .entry)
        await router.handle(.payQR(rawQR), from: .journey)
        #expect(env.steps.last == "abandon")
        #expect(env.landings == [.journey(.scanner)])
    }

    @Test func routerPrefetchesHomeAndNeverShowsIt() async {
        await router.handle(.scanAndPay, from: .entry)
        await router.handle(.payQR(rawQR), from: .journey)
        #expect(env.steps.contains("prefetchHome"))
        #expect(!env.steps.contains("loadHome") && !env.steps.contains("revealHome"))
    }

    @Test func peekAndProductTilesNeverAsk() async {
        await router.handle(.overseas, from: .entry)
        await router.handle(.apply, from: .shell)
        #expect(env.faceIDPrompts.isEmpty)
        #expect(env.landings == [.journey(.placeholder("Overseas Transfer")), .applyTab])
    }
}
