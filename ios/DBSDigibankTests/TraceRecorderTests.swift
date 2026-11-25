import Foundation
import Testing
@testable import digibank

@Suite("TraceRecorder")
struct TraceRecorderTests {
    private func span(_ name: String, _ start: Double, _ end: Double) -> TraceSpan {
        TraceSpan(name: name, kind: .backend, startMs: start, endMs: end, criticalPath: true)
    }

    private func run(summaryEnd: Double, attestEnd: Double, flow: FlowMode) -> [String: Bool] {
        let spans = TraceRecorder.resolve([
            span(TraceRecorder.faceID, 0, 1000), span(TraceRecorder.attest, 0, attestEnd),
            span(TraceRecorder.summary, 1000, summaryEnd), span(TraceRecorder.lookup, 1500, 3000),
            span(TraceRecorder.pay, 5000, 6000),
        ], flow: flow)
        return Dictionary(uniqueKeysWithValues: spans.map { ($0.name, $0.criticalPath) })
    }

    @Test func parallelCallsThatFinishEarlyAreOffThePath() {
        let flags = run(summaryEnd: 2800, attestEnd: 900, flow: .router)
        #expect(flags[TraceRecorder.summary] == false)
        #expect(flags[TraceRecorder.attest] == false)
    }

    @Test func parallelCallsThatHoldTheRunUpAreOnThePath() {
        let flags = run(summaryEnd: 3400, attestEnd: 1200, flow: .router)
        #expect(flags[TraceRecorder.summary] == true)
        #expect(flags[TraceRecorder.attest] == true)
    }

    @Test func sequentialKeepsHomeOnThePath() {
        #expect(run(summaryEnd: 1200, attestEnd: 900, flow: .sequential)[TraceRecorder.summary] == true)
    }

    @Test func waitingAtTheFormIsTheUsersTime() {
        let spans = TraceRecorder.resolve([span(TraceRecorder.lookup, 0, 100), span(TraceRecorder.pay, 900, 1000)], flow: .router)
        #expect(spans.first { $0.kind == .user }.map { [$0.startMs, $0.endMs] } == [100, 900])
    }

    @Test func tokensFromAnEarlierRunAreIgnored() {
        let recorder = TraceRecorder()
        recorder.begin(flow: .router, multiplier: 1)
        let old = recorder.start("old", .ui)
        recorder.begin(flow: .router, multiplier: 1)
        recorder.end(old)
        #expect(recorder.finish()?.spans.isEmpty == true)
    }

    @Test func readsServerTiming() {
        #expect(TraceRecorder.serverTiming("delay;dur=900, app;dur=12.5") == ["delay": 900, "app": 12.5])
    }

    @Test func stepUpBindingMatchesTheServer() {
        let payment = StepUpPayment(fromAccountId: "acc-1", proxyType: "MOBILE", proxyValue: "91234567", amount: "12.50", idempotencyKey: "k")
        #expect(payment.binding == "a8539d834d885f18eb16689ea59982e5ad8b483331ba20a70798aabc354f432d")
    }
}
