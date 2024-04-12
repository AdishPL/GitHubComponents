//
//  File.swift
//  
//
//  Created by Adrian Kaczmarek on 24/02/2024.
//

import SwiftUI

public struct GitHubUsers: View {
    public var body: some View {
        Text("Test")
    }
}

public struct GitHubUser: Codable, Hashable, Identifiable {
    public var id: Int64
    public var login: String
    public var avatarUrl: String?

    public init(id: Int64, login: String, avatarUrl: String? = nil) {
        self.id = id
        self.login = login
        self.avatarUrl = avatarUrl
    }
}

public protocol Endpoint {
    var baseUrl: URL { get }
    var path: String { get }
    var method: String { get }
    var queryParameters: [String: String]? { get }
    var body: Data? { get }
    var middleware: [RequestMiddleware]? { get }
}

public protocol URLSessionDataTaskProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

// Extend URLSession to conform to this protocol
extension URLSession: URLSessionDataTaskProtocol {}

public protocol NetworkingServiceProtocol {
    func request<T: Decodable>(from endpoint: Endpoint) async throws -> T
}

public final class BaseNetworkingService: NetworkingServiceProtocol {
    private let session: URLSessionDataTaskProtocol

    public init(session: URLSessionDataTaskProtocol = URLSession.shared) {
        self.session = session
    }

    // Improve with errors
    public func request<T: Decodable>(from endpoint: Endpoint) async throws -> T {
        var urlComponents = URLComponents(url: endpoint.baseUrl.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: true)!
        urlComponents.queryItems = endpoint.queryParameters?.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = urlComponents.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.httpBody = endpoint.body

        // Apply middleware to the request
        endpoint.middleware?.forEach { $0.prepare(&request) }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

extension Endpoint where Self: GitHubEndpoint {
    public var baseUrl: URL {
        URL(string: "https://api.github.com")!
    }
}

public protocol GitHubEndpoint: Endpoint {}

public struct GitHubUsersEndpoint: GitHubEndpoint {
    public var path: String = "/search/users"
    public var method: String = "GET"
    public var queryParameters: [String : String]? = nil
    public var body: Data? = nil
    public var middleware: [RequestMiddleware]? = [
        HeadersMiddleware(headers: ["Accept": "application/vnd.github.v3+json"])
    ]

    // Added an initializer to accept a query
    public init(query: String) {
        self.queryParameters = ["q": query]
    }
}

public class GitHubService {
    struct GitHubSearchResults: Decodable {
        let items: [GitHubUser]
    }

    let networking: NetworkingServiceProtocol

    public init(networking: NetworkingServiceProtocol = BaseNetworkingService()) {
        self.networking = networking
    }

    public func fetchUsers(query: String) async throws -> [GitHubUser] {
        let fetchedResult: GitHubSearchResults = try await networking.request(from: GitHubUsersEndpoint(query: query))

        return fetchedResult.items
    }
}

public protocol RequestMiddleware {
    func prepare(_ request: inout URLRequest)
}

struct HeadersMiddleware: RequestMiddleware {
    let headers: [String: String]

    init(headers: [String: String]) {
        self.headers = headers
    }

    func prepare(_ request: inout URLRequest) {
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
    }
}
