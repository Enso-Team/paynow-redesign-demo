import Foundation

enum Service: String, Sendable, CaseIterable {
    case auth, account, lookup, payment

    var port: Int {
        switch self {
        case .auth: 8081
        case .account: 8082
        case .lookup: 8083
        case .payment: 8084
        }
    }

    static let host = Bundle.main.object(forInfoDictionaryKey: "DBSBackendHost") as? String ?? "localhost"

    func url(_ path: String) -> URL? {
        let slashed = path.hasPrefix("/") ? path : "/" + path
        return URL(string: "http://\(Self.host):\(port)\(slashed)")
    }
}

struct APIRequest: Sendable {
    var service: Service
    var path: String
    var method: String = "GET"
    var body: Data?
    var headers: [String: String] = [:]

    func urlRequest(bearer: String?) throws -> URLRequest {
        guard let url = service.url(path) else { throw APIError.badPath(path) }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method.uppercased()
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        return request
    }
}

struct APIResponse: Sendable {
    var status: Int
    var data: Data
    var headers: [String: String]

    var errorCode: String? {
        (try? JSONDecoder().decode(ErrorBody.self, from: data))?.code
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

struct ErrorBody: Codable, Sendable {
    var code: String
    var message: String?
}

enum APIError: Error, LocalizedError, Equatable {
    case badPath(String)
    case transport(String)
    case server(status: Int, code: String?)

    var errorDescription: String? {
        switch self {
        case .badPath(let path): "Bad path \(path)"
        case .transport(let message): "Can't reach Demo Bank right now. \(message)"
        case .server(let status, let code): "Server error \(status) \(code ?? "")"
        }
    }
}

protocol HTTPTransport: Sendable {
    func perform(_ request: URLRequest) async throws -> APIResponse
}

struct URLSessionTransport: HTTPTransport {
    var session: URLSession = .shared

    func perform(_ request: URLRequest) async throws -> APIResponse {
        do {
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            var headers: [String: String] = [:]
            for (key, value) in http?.allHeaderFields ?? [:] {
                headers["\(key)"] = "\(value)"
            }
            return APIResponse(status: http?.statusCode ?? 0, data: data, headers: headers)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }
}

/// Calls that need no session token (device binding and session setup).
struct PublicAPI: Sendable {
    var transport: HTTPTransport

    func post<Body: Encodable>(_ service: Service, _ path: String, _ body: Body) async throws -> APIResponse {
        let request = APIRequest(service: service, path: path, method: "POST", body: try JSONEncoder().encode(body))
        return try await transport.perform(request.urlRequest(bearer: nil))
    }
}
