import SwiftUI
import Testing
import UIKit
@testable import digibank

/// Renders the entry page with Peek at each phase into `ios/screenshots/peek-render-1…4.png` (gitignored),
/// to compare with the web's peek-1…4.
@MainActor
@Suite("PeekRender")
struct PeekRenderTests {
    static let sample = PeekBalance(
        balance: "2,109.77", currency: "SGD", asOf: "2026-11-20T09:32:00.123Z",
        transactions: [
            PeekTransaction(type: "PayNow Transfer", date: "2026-11-20", amount: "-12.50"),
            PeekTransaction(type: "FAST Payment / Receipt", date: "2026-11-18", amount: "500.00"),
            PeekTransaction(type: "NETS Purchase", date: "2026-11-16", amount: "-8.40"),
        ])

    @Test func rendersEachPhase() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let hold = PeekHold()
        let host = UIHostingController(rootView: EntryView(hold: hold).environment(AppModel()).preferredColorScheme(.dark))
        window.rootViewController = host
        window.windowLevel = .alert + 2
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(800))

        let backdrop = try #require(PeekBackdrop.capture(window))
        let folder = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "screenshots")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let phases: [(PeekHold.Phase, PeekBalance?)] = [(.bars, nil), (.blank, nil), (.compact, Self.sample), (.expanded, Self.sample)]
        for (index, (phase, data)) in phases.enumerated() {
            hold.show(phase, data: data, backdrop: backdrop)
            try await Task.sleep(for: .milliseconds(400))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let png = try #require(image.pngData())
            try png.write(to: folder.appending(path: "peek-render-\(index + 1).png"))
        }
    }
}
