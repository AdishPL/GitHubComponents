//
//  Networking.swift
//  
//
//  Created by Adrian Kaczmarek on 24/02/2024.
//

import XCTest
@testable import Networking

final class Networking: XCTestCase {
    class MockURLSession: URLSessionDataTaskProtocol {
        var nextData: Data?
        var nextResponse: URLResponse?
        var nextError: Error?

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            if let error = nextError {
                throw error
            }
            guard let data = nextData, let response = nextResponse else {
                fatalError("MockURLSession data and response should not be nil")
            }
            return (data, response)
        }
    }

    // create test for query parameter

    func testFetchGitHubUsersSuccess() async {
        let jsonString = """
        [
          {
            "login": "octocat",
            "id": 1,
            "avatar_url": "https://avatars.githubusercontent.com/u/1?v=4",
            "type": "User",
            "site_admin": false
          },
          {
            "login": "doe",
            "id": 2,
            "avatar_url": "https://avatars.githubusercontent.com/u/2?v=4",
            "type": "User",
            "site_admin": false
          }
        ]
        """

        guard let mockData = jsonString.data(using: .utf8) else {
            fatalError("Unable to convert JSON string to Data")
        }

        let mockSession = MockURLSession()
        let service = BaseNetworkingService(session: mockSession)

        // Simulate a successful fetch
        let mockResponse = HTTPURLResponse(url: URL(string: "https://api.github.com/users")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        mockSession.nextData = mockData
        mockSession.nextResponse = mockResponse

        do {
            let users: [GitHubUser] = try await service.request(from: GitHubUsersEndpoint(query: "test"))
            XCTAssertEqual(users.first?.login, "octocat")
        } catch {
            XCTFail("Expected successful user fetch, but received an error: \(error)")
        }
    }

    func testFetchGitHubUsersFailure() async {
        let mockSession = MockURLSession()
        let service = BaseNetworkingService(session: mockSession)

        // Simulate a network failure
        mockSession.nextError = NSError(domain: "TestError", code: -1, userInfo: nil)

        do {
            let _: [GitHubUser] = try await service.request(from: GitHubUsersEndpoint(query: "test"))
            XCTFail("Expected failure, but request succeeded")
        } catch {
            // Expected failure, perform additional error assertions here if necessary
        }
    }
}

class MockHeadersMiddleware: RequestMiddleware {
    var headersToApply: [String: String]
    var didPrepareRequest: Bool = false
    var appliedHeaders: [String: String] = [:]

    init(headers: [String: String]) {
        self.headersToApply = headers
    }

    func prepare(_ request: inout URLRequest) {
        didPrepareRequest = true
        headersToApply.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
            appliedHeaders[key] = value
        }
    }
}

class MiddlewareTests: XCTestCase {
    func testGitHubUsersEndpointMiddleware() {
        // Initialize the mock middleware with expected headers
        let expectedHeaders = ["Accept": "application/vnd.github.v3+json"]
        let mockMiddleware = MockHeadersMiddleware(headers: expectedHeaders)

        // Create an instance of GitHubUsersEndpoint with the mock middleware
        var endpoint = GitHubUsersEndpoint(query: "test") // Assuming GitHubUsersEndpoint conforms to a protocol where you can inject middleware
        endpoint.middleware = [mockMiddleware]

        // Create a URLRequest and apply the middleware
        var request = URLRequest(url: URL(string: "https://api.github.com/users")!)
        endpoint.middleware?.forEach { $0.prepare(&request) }

        // Verify that the middleware was called and the headers were applied correctly
        XCTAssertTrue(mockMiddleware.didPrepareRequest, "Middleware did not prepare the request.")
        XCTAssertEqual(request.allHTTPHeaderFields, expectedHeaders, "Headers applied by the middleware do not match the expected headers.")
    }
}
