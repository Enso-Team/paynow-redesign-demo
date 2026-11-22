import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// The React PayNow form micro-frontend in a WKWebView. The bundle is served from the app bundle
/// under `paynow://form/`. A shim injected at document start implements `window.paynowHost` over
/// `window.webkit.messageHandlers.paynow` with promise ids. The form never holds the session token.
struct PayNowFormView: View {
    @Environment(AppModel.self) private var app
    let initial: PaynowInit

    var body: some View {
        PaynowWebView(initial: initial, bridge: PaynowBridge(app: app))
            .ignoresSafeArea(edges: .bottom)
            .background(.white)
            .navigationBarBackButtonHidden()
    }
}

/// Native side of the PaynowHost interface.
@MainActor
struct PaynowBridge {
    let app: AppModel

    func api(service: String, path: String, method: String?, body: String?, headers: [String: String]) async throws
        -> (status: Int, body: Any) {
        guard let service = Service(rawValue: service), service != .auth else {
            throw APIError.badPath("\(service)\(path)")
        }
        let request = APIRequest(service: service, path: path, method: method ?? "GET",
                                 body: body.map { Data($0.utf8) }, headers: headers)
        let response = try await app.session.send(request)
        let json: Any? = try? JSONSerialization.jsonObject(with: response.data, options: .fragmentsAllowed)
        let parsed: Any = json ?? (response.data.isEmpty ? NSNull() : String(decoding: response.data, as: UTF8.self))
        return (response.status, parsed)
    }

    func done(_ result: PaymentResult) { app.paymentFinished(result) }

    func close() { app.closeForm() }

    func touched() { app.userInteracted() }
}

struct PaynowWebView: UIViewRepresentable {
    let initial: PaynowInit
    let bridge: PaynowBridge

    static let scheme = "paynow"
    static let entry = URL(string: "paynow://form/index.html")!

    func makeCoordinator() -> Coordinator { Coordinator(bridge: bridge) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(BundleSchemeHandler(), forURLScheme: Self.scheme)
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: Self.shim(initial), injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
        controller.add(context.coordinator, name: "paynow")
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        #if DEBUG
        webView.isInspectable = true
        #endif
        context.coordinator.webView = webView
        webView.load(URLRequest(url: Self.entry))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "paynow")
    }

    static func shim(_ initial: PaynowInit) -> String {
        let initJSON = (try? String(decoding: JSONEncoder().encode(initial), as: UTF8.self)) ?? "{}"
        return """
        (function () {
          var pending = {};
          var seq = 0;
          function post(message) { window.webkit.messageHandlers.paynow.postMessage(JSON.stringify(message)); }
          window.__PAYNOW_INIT__ = \(initJSON);
          window.__paynowSettle = function (id, ok, payload) {
            var p = pending[id];
            if (!p) return;
            delete pending[id];
            if (ok) p.resolve(payload); else p.reject(new Error(payload));
          };
          window.paynowHost = {
            api: function (service, path, init) {
              init = init || {};
              return new Promise(function (resolve, reject) {
                var id = ++seq;
                pending[id] = { resolve: resolve, reject: reject };
                var body = init.body === undefined ? null
                  : (typeof init.body === 'string' ? init.body : JSON.stringify(init.body));
                post({ kind: 'api', id: id, service: service, path: path,
                       method: init.method || 'GET', body: body, headers: init.headers || {} });
              });
            },
            done: function (result) { post({ kind: 'done', result: result }); },
            close: function () { post({ kind: 'close' }); },
            pickContact: function () {
              return new Promise(function (resolve, reject) {
                var id = ++seq;
                pending[id] = { resolve: resolve, reject: reject };
                post({ kind: 'pickContact', id: id });
              });
            }
          };
          // Taps and typing in the form count as activity for the session's idle clock.
          var lastTouch = 0;
          function touched() {
            var now = Date.now();
            if (now - lastTouch < 5000) return;
            lastTouch = now;
            post({ kind: 'touch' });
          }
          ['pointerdown', 'keydown', 'input'].forEach(function (type) {
            document.addEventListener(type, touched, { capture: true, passive: true });
          });
        })();
        """
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, UIAdaptivePresentationControllerDelegate {
        let bridge: PaynowBridge
        weak var webView: WKWebView?
        private var closed = false
        private var contactRequest: Int?
        private weak var contactsSheet: UIViewController?

        init(bridge: PaynowBridge) {
            self.bridge = bridge
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let text = message.body as? String,
                  let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
                  let kind = json["kind"] as? String
            else { return }
            switch kind {
            case "api": handleAPI(json)
            case "done":
                guard let raw = json["result"],
                      let data = try? JSONSerialization.data(withJSONObject: raw),
                      let result = try? JSONDecoder().decode(LooseResult.self, from: data)
                else { return }
                bridge.done(result.value)
            case "touch": bridge.touched()
            case "pickContact": pickContact(json["id"] as? Int)
            case "close":
                // Once per form: the keyboard goes first, then the form.
                guard !closed else { return }
                closed = true
                webView?.endEditing(true)
                bridge.close()
            default: break
            }
        }

        /// Our contacts sheet. It asks for Contacts access on first use and lists Singapore mobiles only.
        /// Resolves `{name, phone}` for a picked row, or null when closed. Contact data stays on the phone.
        private func pickContact(_ id: Int?) {
            guard let id else { return }
            guard contactRequest == nil, let presenter = webView?.window?.rootViewController?.topmostPresented else {
                return settle(id, ok: true, payload: NSNull())
            }
            contactRequest = id
            webView?.endEditing(true)
            let sheet = UIHostingController(rootView: ContactsSheet { [weak self] entry in
                self?.finishPick(entry.map { ["name": $0.name, "phone": $0.mobile] } ?? NSNull())
            })
            sheet.presentationController?.delegate = self
            contactsSheet = sheet
            presenter.present(sheet, animated: true)
        }

        nonisolated func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            MainActor.assumeIsolated { finishPick(NSNull()) }
        }

        private func finishPick(_ payload: Any) {
            guard let id = contactRequest else { return }
            contactRequest = nil
            if let sheet = contactsSheet, sheet.presentingViewController != nil { sheet.dismiss(animated: true) }
            contactsSheet = nil
            settle(id, ok: true, payload: payload)
        }

        private func handleAPI(_ json: [String: Any]) {
            guard let id = json["id"] as? Int else { return }
            let service = json["service"] as? String ?? ""
            let path = json["path"] as? String ?? "/"
            let method = json["method"] as? String
            let body = json["body"] as? String
            let headers = (json["headers"] as? [String: Any] ?? [:]).compactMapValues { "\($0)" }
            Task {
                do {
                    let response = try await bridge.api(service: service, path: path, method: method,
                                                        body: body, headers: headers)
                    let payload: [String: Any] = ["status": response.status, "body": response.body]
                    settle(id, ok: true, payload: payload)
                } catch {
                    settle(id, ok: false, payload: error.localizedDescription)
                }
            }
        }

        private func settle(_ id: Int, ok: Bool, payload: Any) {
            guard let data = try? JSONSerialization.data(withJSONObject: [payload], options: .fragmentsAllowed),
                  let array = String(data: data, encoding: .utf8)
            else { return }
            webView?.evaluateJavaScript("window.__paynowSettle(\(id), \(ok), \(array)[0]);")
        }
    }
}

/// Accepts amounts as strings or numbers from the form.
private struct LooseResult: Decodable {
    let value: PaymentResult

    enum CodingKeys: String, CodingKey { case paymentId, status, amount, maskedName }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String {
            if let s = try? c.decode(String.self, forKey: key) { return s }
            if let d = try? c.decode(Double.self, forKey: key) { return String(format: "%.2f", d) }
            return ""
        }
        value = PaymentResult(paymentId: text(.paymentId), status: text(.status),
                              amount: text(.amount), maskedName: text(.maskedName))
    }
}

/// Serves `paynow://form/<path>` from the bundled `PaynowForm` folder, so module scripts and
/// absolute asset paths load with proper MIME types.
final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    private let root = Bundle.main.url(forResource: "PaynowForm", withExtension: nil)

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, let root else {
            return task.didFailWithError(URLError(.fileDoesNotExist))
        }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        var file = root.appendingPathComponent(String(path.dropFirst()))
        if !FileManager.default.fileExists(atPath: file.path) {
            file = root.appendingPathComponent("index.html")
        }
        guard let data = try? Data(contentsOf: file) else {
            return task.didFailWithError(URLError(.fileDoesNotExist))
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": mime == "application/javascript" ? "text/javascript" : mime,
            "Content-Length": "\(data.count)",
            "Access-Control-Allow-Origin": "*",
        ])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

private extension UIViewController {
    /// The view controller currently on top, to present the contact picker from.
    var topmostPresented: UIViewController {
        presentedViewController?.topmostPresented ?? self
    }
}
