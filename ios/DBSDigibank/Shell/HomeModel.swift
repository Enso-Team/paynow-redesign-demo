import Foundation

/// Home's account data. Refreshes in the background with ETag. A failed refresh keeps the last data.
@MainActor
@Observable
final class HomeModel {
    private(set) var summary: AccountsSummary?
    private(set) var lastUpdated: Date?
    private(set) var refreshFailed = false
    @ObservationIgnored private var raw: Data?
    @ObservationIgnored private var etag: String?
    @ObservationIgnored private let session: SessionManager
    @ObservationIgnored private var inFlight: Task<Void, Never>?

    init(session: SessionManager) {
        self.session = session
    }

    func refresh() async {
        if let inFlight { return await inFlight.value }
        let task = Task { await load() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func load() async {
        var request = APIRequest(service: .account, path: "/accounts/summary")
        if let etag, summary != nil { request.headers["If-None-Match"] = etag }
        do {
            let response = try await session.send(request, interactive: false)
            switch response.status {
            case 304:
                break
            case 200:
                raw = response.data
                summary = try response.decode(AccountsSummary.self)
                etag = response.header("ETag")
            default:
                throw APIError.server(status: response.status, code: response.errorCode)
            }
            lastUpdated = .now
            refreshFailed = false
        } catch {
            refreshFailed = true
        }
    }

    /// The summary for the PayNow form: the fetch under way, or one from the last minute.
    func freshSummary() async -> Data? {
        if let inFlight { await inFlight.value }
        guard !refreshFailed, let lastUpdated, Date.now.timeIntervalSince(lastUpdated) < 60 else { return nil }
        return raw
    }

    func clear() {
        raw = nil
        summary = nil
        etag = nil
        lastUpdated = nil
        refreshFailed = false
    }
}
