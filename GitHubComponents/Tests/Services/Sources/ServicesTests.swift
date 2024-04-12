//
//  ServicesTests.swift
//  
//
//  Created by Adrian Kaczmarek on 10/03/2024.
//

@testable import Networking
@testable import Services
@testable import Persistence

import XCTest
import CoreData

class MockGitHubService: GitHubService {
    var usersByQuery: [String: [GitHubUser]] = [:]
    var error: Error?

    override func fetchUsers(query: String) async throws -> [GitHubUser] {
        if let error = error {
            throw error
        }
        // Return the users that match the given query, defaulting to an empty array if no match is found
        return usersByQuery[query, default: []]
    }
}

class MockNetworkMonitor: NetworkMonitoring {
    var isConnected: Bool = false

    func startMonitoring() {
        // No operation in mock
    }

    func stopMonitoring() {
        // No operation in mock
    }
}

class InMemoryPersistentContainerFactory: PersistentContainerFactoryProtocol {
    func createContainer(named name: String) -> PersistentContainerProtocol {
        let mom = NSManagedObjectModel.mergedModel(from: [PersistenceModuleBundle])

        let container = NSPersistentContainer(name: name, managedObjectModel: mom!)

        // Create a description for an in-memory store
        let description = NSPersistentStoreDescription()
        description.url = URL(fileURLWithPath: "/dev/null")
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]

        return container
    }
}

final class CoreDataUserServiceTests: XCTestCase {
    var coreDataCacheService: CoreDataCacheService!
    var persistentContainerService: PersistentContainerService!
    var mockPersistenContainer: NSPersistentContainer!
    var mockGithubService: MockGitHubService!
    var mockNetworkMonitor: MockNetworkMonitor!

    override func setUp() {
        super.setUp()
        persistentContainerService = .init(containerFactory: InMemoryPersistentContainerFactory())
        mockPersistenContainer = (persistentContainerService.container(forModel: .GithubUsersList) as! NSPersistentContainer)
        coreDataCacheService = CoreDataCacheService(persistentContainer: mockPersistenContainer)
        mockGithubService = MockGitHubService()
        mockNetworkMonitor = MockNetworkMonitor()
    }

    override func tearDown() {
        mockGithubService = nil
        mockNetworkMonitor = nil
        persistentContainerService = nil
        mockPersistenContainer = nil
        coreDataCacheService = nil
        super.tearDown()
    }

    func testFetchUsersWhenOffline() async throws {
        mockNetworkMonitor.isConnected = false // Simulate offline mode

        let service = CoreDataUserService(gitHubService: mockGithubService,
                                          coreDataCacheService: coreDataCacheService,
                                          networkMonitor: mockNetworkMonitor)

        do {
            let users = try await service.fetchCachedUsers(matching: "test")
            // Assertions for offline fetch behavior
            debugPrint(users.count)
        } catch {
            XCTFail("Failed with error: \(error)")
        }
    }

    func testFetchUsersOnceWhenOnline() async throws {
        mockNetworkMonitor.isConnected = true // Simulate online mode

        let service = CoreDataUserService(gitHubService: mockGithubService,
                                          coreDataCacheService: coreDataCacheService,
                                          networkMonitor: mockNetworkMonitor)

        // Mocked models for query `test`
        let testUsers = [GitHubUser(id: 1, login: "testUser1", avatarUrl: "http://example.com/avatar1.jpg"),
                         GitHubUser(id: 2, login: "testUser2", avatarUrl: "http://example.com/avatar2.jpg")]

        // Setting up mock responses for different queries
        mockGithubService.usersByQuery["testQuery1"] = testUsers

        do {
            let users = try await service.fetchAndSaveUsersFromEndpoint(matching: "testQuery1")
            // Assertions for online fetch behavior
            XCTAssertEqual(users.count, 2)
            XCTAssertEqual(users, testUsers)
        } catch {
            XCTFail("Failed with error: \(error)")
        }
    }

    func testFetchUsersOnceOnlineThenOffline() async throws {
        mockNetworkMonitor.isConnected = true // Simulate online mode

        let service = CoreDataUserService(gitHubService: mockGithubService,
                                          coreDataCacheService: coreDataCacheService,
                                          networkMonitor: mockNetworkMonitor)

        // Mocked models for query `test`
        let testUsers = [GitHubUser(id: 1, login: "testUser1", avatarUrl: "http://example.com/avatar1.jpg"),
                         GitHubUser(id: 2, login: "testUser2", avatarUrl: "http://example.com/avatar2.jpg")]

        // Setting up mock responses for different queries
        mockGithubService.usersByQuery["testQuery1"] = testUsers

        do {
            let users = try await service.fetchAndSaveUsersFromEndpoint(matching: "testQuery1")
            // Assertions for online fetch behavior
            XCTAssertEqual(users.count, 2)
            XCTAssertEqual(users, testUsers)
        } catch {
            XCTFail("Failed with error: \(error)")
        }

        mockNetworkMonitor.isConnected = false // Simulate offline mode

        // Fetch should happen in persistence layer
        let users = try await service.fetchCachedUsers(matching: "testQuery1")
        // Assertions for offline fetch behavior
        XCTAssertEqual(users.count, 2)
        XCTAssertEqual(users, testUsers)
    }

    func testFetchWithDifferentQueriesWhenPersisted() async throws {
        mockNetworkMonitor.isConnected = true // Simulate online mode

        let service = CoreDataUserService(gitHubService: mockGithubService,
                                          coreDataCacheService: coreDataCacheService,
                                          networkMonitor: mockNetworkMonitor)

        let query1 = "test"
        let query2 = "test2"

        // Mocked models for query `test`
        let queryTestUsers = [GitHubUser(id: 1, login: "testUser1", avatarUrl: "http://example.com/avatar1.jpg"),
                              GitHubUser(id: 2, login: "testUser2", avatarUrl: "http://example.com/avatar2.jpg")]
        // Mocked models for query `test2`
        let queryTest2Users = [GitHubUser(id: 123, login: "testUser123", avatarUrl: "http://example.com/avatar1.jpg"),
                               GitHubUser(id: 4223, login: "testUser4223", avatarUrl: "http://example.com/avatar2.jpg")]

        // Setting up mock responses for different queries
        mockGithubService.usersByQuery[query1] = queryTestUsers
        mockGithubService.usersByQuery[query2] = queryTest2Users

        do {
            let testUsers = try await service.fetchAndSaveUsersFromEndpoint(matching: query1)
            let testUsers2 = try await service.fetchAndSaveUsersFromEndpoint(matching: query2)
            // Assertions for online fetch behavior
            XCTAssertEqual(testUsers.count, 2)
            XCTAssertEqual(testUsers, queryTestUsers)
            XCTAssertEqual(testUsers2.count, 2)
            XCTAssertEqual(testUsers2, queryTest2Users)
        } catch {
            XCTFail("Failed with error: \(error)")
        }

        mockNetworkMonitor.isConnected = false // Simulate offline mode

        // Fetch should happen in persistence layer
        let testUsers = try await service.fetchCachedUsers(matching: query1)
        let testUsers2 = try await service.fetchCachedUsers(matching: query2)
        // Assertions for offline fetch behavior
        XCTAssertEqual(testUsers.count, 2)
        XCTAssertEqual(testUsers, queryTestUsers)
        XCTAssertEqual(testUsers2.count, 2)
        XCTAssertEqual(testUsers2, queryTest2Users)
    }

    func testFetchWithDifferentQueriesWhenOneIsNotPersisted() async throws {
        mockNetworkMonitor.isConnected = true // Simulate online mode

        let service = CoreDataUserService(gitHubService: mockGithubService,
                                          coreDataCacheService: coreDataCacheService,
                                          networkMonitor: mockNetworkMonitor)

        let query1 = "test"
        let query2 = "test2"

        // Mocked models for query `test`
        let queryTestUsers = [GitHubUser(id: 1, login: "testUser1", avatarUrl: "http://example.com/avatar1.jpg"),
                              GitHubUser(id: 2, login: "testUser2", avatarUrl: "http://example.com/avatar2.jpg")]

        // Setting up mock responses for different queries
        mockGithubService.usersByQuery[query1] = queryTestUsers

        do {
            let testUsers = try await service.fetchAndSaveUsersFromEndpoint(matching: query1)
            let testUsers2 = try await service.fetchAndSaveUsersFromEndpoint(matching: query2)
            // Assertions for online fetch behavior
            XCTAssertEqual(testUsers.count, 2)
            XCTAssertEqual(testUsers, queryTestUsers)
            XCTAssertEqual(testUsers2.count, 0)
        } catch {
            XCTFail("Failed with error: \(error)")
        }

        mockNetworkMonitor.isConnected = false // Simulate offline mode

        // Fetch should happen in persistence layer
        let testUsers = try await service.fetchCachedUsers(matching: query1)
        let testUsers2 = try await service.fetchCachedUsers(matching: query2)
        // Assertions for offline fetch behavior
        XCTAssertEqual(testUsers.count, 2)
        XCTAssertEqual(testUsers, queryTestUsers)
        XCTAssertEqual(testUsers2.count, 0)
    }

    func testFetchQueryWhenUsersHasChanged() async {
        mockNetworkMonitor.isConnected = true // Simulate online mode

        let service = CoreDataUserService(gitHubService: mockGithubService,
                                          coreDataCacheService: coreDataCacheService,
                                          networkMonitor: mockNetworkMonitor)

        let query = "test"

        // Mocked models for query `test`
        let queryTestUsersFirstFetch = [GitHubUser(id: 1, login: "testUser1", avatarUrl: "http://example.com/avatar1.jpg"),
                                        GitHubUser(id: 2, login: "testUser2", avatarUrl: "http://example.com/avatar2.jpg")]

        mockGithubService.usersByQuery[query] = queryTestUsersFirstFetch

        do {
            let testUsers = try await service.fetchAndSaveUsersFromEndpoint(matching: query)
            // Assertions for online fetch behavior
            XCTAssertEqual(testUsers.count, 2)
            XCTAssertEqual(testUsers, queryTestUsersFirstFetch)
        } catch {
            XCTFail("Failed with error: \(error)")
        }

        // Mocked models for query `test`
        let queryTestUsersSecondFetch = [GitHubUser(id: 1, login: "testUserOne", avatarUrl: "http://example.com/avatar1.jpg"),
                                        GitHubUser(id: 2, login: "testUserSecond", avatarUrl: "http://example.com/avatar2.jpg")]

        mockGithubService.usersByQuery[query] = queryTestUsersSecondFetch

        do {
            let testUsers = try await service.fetchAndSaveUsersFromEndpoint(matching: query)
            // Assertions for online fetch behavior
            XCTAssertEqual(testUsers.count, 2)
            XCTAssertEqual(testUsers, queryTestUsersSecondFetch)
        } catch {
            XCTFail("Failed with error: \(error)")
        }
    }

    func testFetchQueryUsersHasChangedWhenOffline() async throws {
        mockNetworkMonitor.isConnected = true // Simulate online mode

        let service = CoreDataUserService(gitHubService: mockGithubService,
                                          coreDataCacheService: coreDataCacheService,
                                          networkMonitor: mockNetworkMonitor)

        let query = "test"

        // Mocked models for query `test`
        let queryTestUsersFirstFetch = [GitHubUser(id: 1, login: "testUser1", avatarUrl: "http://example.com/avatar1.jpg"),
                                        GitHubUser(id: 2, login: "testUser2", avatarUrl: "http://example.com/avatar2.jpg")]

        mockGithubService.usersByQuery[query] = queryTestUsersFirstFetch

        _ = try await service.fetchAndSaveUsersFromEndpoint(matching: query)

        // Mocked models for query `test`
        let queryTestUsersSecondFetch = [GitHubUser(id: 1, login: "testUserOne", avatarUrl: "http://example.com/avatar1.jpg"),
                                        GitHubUser(id: 2, login: "testUserSecond", avatarUrl: "http://example.com/avatar2.jpg")]

        mockGithubService.usersByQuery[query] = queryTestUsersSecondFetch

        _ = try await service.fetchAndSaveUsersFromEndpoint(matching: query)

        mockNetworkMonitor.isConnected = false // Simulate offline mode

        let offlineUsers = try await service.fetchCachedUsers(matching: query)

        XCTAssertEqual(offlineUsers.count, 2)
        XCTAssertEqual(offlineUsers, queryTestUsersSecondFetch)
    }
    // Additional tests for online behavior, error handling, etc.
}
