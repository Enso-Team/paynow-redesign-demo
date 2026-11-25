import Foundation
import UIKit

struct TraceSpan: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable { case ui, biometric, backend, user, screen }

    var name: String
    var kind: Kind
    var startMs: Double
    var endMs: Double
    var criticalPath: Bool
    var status: Int?
    /// From the Server-Timing header: the injected delay, and the service's own work.
    var serverDelayMs: Double?
    var serverAppMs: Double?

    enum CodingKeys: String, CodingKey {
        case name, kind, status
        case startMs = "start_ms", endMs = "end_ms", criticalPath = "critical_path"
        case serverDelayMs = "server_delay_ms", serverAppMs = "server_app_ms"
    }
}

struct RunTrace: Codable, Sendable {
    var runId: String
    var flow: String
    var multiplier: Int
    var startedAt: String
    var source: String
    var biometricMocked: Bool
    var spans: [TraceSpan]

    enum CodingKeys: String, CodingKey {
        case flow, multiplier, source, spans
        case runId = "run_id", startedAt = "started_at", biometricMocked = "biometric_mocked"
    }
}

/// Times one Scan & Pay run from the tap to the Sent screen, on the monotonic clock.
final class TraceRecorder: @unchecked Sendable {
    static let shared = TraceRecorder()

    static let pay = "POST /payments/paynow"
    static let lookup = "GET /paynow/lookup"
    static let summary = "GET /accounts/summary"
    static let attest = "POST /auth/attest"
    static let faceID = "Face ID"

    struct Token: Sendable {
        fileprivate let run: UUID
        fileprivate let index: Int
    }

    private struct Run {
        let id = UUID()
        let flow: FlowMode
        let multiplier: Int
        let startedAt = Date()
        let origin: TimeInterval
        var biometricMocked = false
        var spans: [TraceSpan] = []
    }

    private let lock = NSLock()
    private let uptime: @Sendable () -> TimeInterval
    private var run: Run?

    init(uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.uptime = uptime
    }

    func begin(flow: FlowMode, multiplier: Int) {
        lock.withLock { run = Run(flow: flow, multiplier: multiplier, origin: uptime()) }
    }

    func cancel() { lock.withLock { run = nil } }

    /// A loading screen is a label over the work it waits for, so it never counts as work itself.
    func startScreen(_ name: String) -> Token? {
        let token = start(name, .screen)
        guard let token else { return nil }
        lock.withLock { if run?.id == token.run { run?.spans[token.index].criticalPath = false } }
        return token
    }

    var isRunning: Bool { lock.withLock { run != nil } }

    func markBiometricMocked() { lock.withLock { run?.biometricMocked = true } }

    func start(_ name: String, _ kind: TraceSpan.Kind) -> Token? {
        lock.withLock {
            guard let current = run else { return nil }
            let now = (uptime() - current.origin) * 1000
            run?.spans.append(TraceSpan(name: name, kind: kind, startMs: now, endMs: -1, criticalPath: true))
            return Token(run: current.id, index: current.spans.count)
        }
    }

    func end(_ token: Token?, response: APIResponse? = nil) {
        guard let token else { return }
        lock.withLock {
            guard let current = run, current.id == token.run else { return }
            var span = current.spans[token.index]
            guard span.endMs < 0 else { return }
            span.endMs = (uptime() - current.origin) * 1000
            if let response {
                span.status = response.status
                let timing = Self.serverTiming(response.header("Server-Timing"))
                span.serverDelayMs = timing["delay"]
                span.serverAppMs = timing["app"]
            }
            run?.spans[token.index] = span
        }
    }

    /// Ends the open span with this name, when its start and end live in different views.
    func end(_ name: String) {
        let token: Token? = lock.withLock {
            guard let current = run,
                  let index = current.spans.lastIndex(where: { $0.name == name && $0.endMs < 0 }) else { return nil }
            return Token(run: current.id, index: index)
        }
        end(token)
    }

    /// Closes the run. Spans still open at the end are left out.
    func finish() -> RunTrace? {
        let closed: Run? = lock.withLock {
            defer { run = nil }
            return run
        }
        guard let closed else { return nil }
        #if targetEnvironment(simulator)
        let source = "simulator"
        #else
        let source = "iphone"
        #endif
        return RunTrace(runId: closed.id.uuidString, flow: closed.flow.rawValue, multiplier: closed.multiplier,
                        startedAt: closed.startedAt.formatted(.iso8601), source: source,
                        biometricMocked: closed.biometricMocked,
                        spans: Self.resolve(closed.spans.filter { $0.endMs >= 0 }, flow: closed.flow))
    }

    /// Adds the wait for the person at the form, and works out which parallel calls held the run up:
    /// attest when it outlives Face ID, and the summary when it outlives the lookup.
    static func resolve(_ recorded: [TraceSpan], flow: FlowMode) -> [TraceSpan] {
        var spans = recorded
        let pay = spans.first { $0.name == Self.pay }
        let beforePay = spans.filter { span in pay.map { span.endMs <= $0.startMs } ?? true }
        let lookupEnd = beforePay.last { $0.name == Self.lookup }?.endMs
        let summaryEnd = beforePay.last { $0.name == Self.summary }?.endMs
        let faceIDEnd = spans.first { $0.name == Self.faceID }?.endMs
        if flow == .router {
            for index in spans.indices {
                let span = spans[index]
                if span.name == Self.attest, let faceIDEnd { spans[index].criticalPath = span.endMs > faceIDEnd }
                if span.name == Self.summary {
                    spans[index].criticalPath = lookupEnd.map { span.endMs > $0 && span.startMs < (pay?.startMs ?? .infinity) } ?? true
                }
            }
        }
        if let pay, let ready = [lookupEnd, summaryEnd].compactMap({ $0 }).max(), ready < pay.startMs {
            spans.append(TraceSpan(name: "Review and tap Pay", kind: .user, startMs: ready, endMs: pay.startMs, criticalPath: true))
        }
        return spans.sorted { $0.startMs < $1.startMs }
    }

    static func serverTiming(_ header: String?) -> [String: Double] {
        var values: [String: Double] = [:]
        for entry in (header ?? "").split(separator: ",") {
            let parts = entry.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let name = parts.first, let duration = parts.first(where: { $0.hasPrefix("dur=") }) else { continue }
            values[name] = Double(duration.dropFirst(4))
        }
        return values
    }
}
