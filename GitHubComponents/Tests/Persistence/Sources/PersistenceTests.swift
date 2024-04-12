//
//  PersistenceTests.swift
//  
//
//  Created by Adrian Kaczmarek on 24/02/2024.
//

import XCTest
import CoreData
@testable import Networking
@testable import Persistence

class MockPersistentContainer: PersistentContainerProtocol {
    var name: String
    var loadPersistentStoresCalled = false
    var optionsSet: [String: NSNumber] = [:]

    init(name: String) {
        self.name = name
    }

    func loadPersistentStores(completionHandler block: @escaping (NSPersistentStoreDescription, Error?) -> Void) {
        loadPersistentStoresCalled = true
        // Call the completion handler with a dummy description and no error
        block(NSPersistentStoreDescription(), nil)
    }

    func setOption(_ option: NSNumber?, forKey key: String) {
        optionsSet[key] = option
    }
    // Add methods to set options as needed
}

class DummyPersistentContainerFactory: PersistentContainerFactoryProtocol {
    func createContainer(named name: String) -> PersistentContainerProtocol {
        return MockPersistentContainer(name: name)
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

final class PersistenceTests: XCTestCase {
    var service: PersistentContainerService!

    override func setUp() {
        super.setUp()
        service = .init(containerFactory: DummyPersistentContainerFactory())
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    func testContainerCreationAndConfiguration() {
        let model = PersistentContainerService.CoreDataModel.GithubUsersList
        guard let container = service.container(forModel: model) as? MockPersistentContainer else {
            XCTFail("Container is not of type MockPersistentContainer")
            return
        }

        // Verify the container was created with the correct model name
        XCTAssertEqual(container.name, model.modelName)

        // Verify options were set correctly
        XCTAssertEqual(container.optionsSet[NSMigratePersistentStoresAutomaticallyOption], NSNumber(value: true))
        XCTAssertEqual(container.optionsSet[NSInferMappingModelAutomaticallyOption], NSNumber(value: true))

        XCTAssertTrue(container.loadPersistentStoresCalled)
    }

    func testContainerReuse() {
        let model = PersistentContainerService.CoreDataModel.GithubUsersList
        let container1 = service.container(forModel: model)
        let container2 = service.container(forModel: model)

        // Verify the same container instance is reused
        XCTAssert(container1 === container2, "Expected to reuse the same container instance for the same model")
    }
}

class CoreDataCacheServiceTests: XCTestCase {
    var coreDataCacheService: CoreDataCacheService!
    var persistentContainerService: PersistentContainerService!
    var mockPersistenContainer: NSPersistentContainer!

    override func setUp() {
        super.setUp()
        persistentContainerService = .init(containerFactory: InMemoryPersistentContainerFactory())
        mockPersistenContainer = (persistentContainerService.container(forModel: .GithubUsersList) as! NSPersistentContainer)
        coreDataCacheService = CoreDataCacheService(persistentContainer: mockPersistenContainer)
    }

    func testFetchModels() async throws {
        // 1. Insert mock data into the in-memory context
        let context = mockPersistenContainer.viewContext
        let newUser = User(context: context)
        newUser.id = 1
        newUser.login = "TestUser"
        newUser.avatarUrl = "http://example.com/avatar.jpg"
        try context.save()

        XCTAssertEqual(mockPersistenContainer.persistentStoreDescriptions.first!.type, NSInMemoryStoreType)
        // 2. Attempt to fetch models
        do {
            let fetchedUsers: [GitHubUser] = try await coreDataCacheService.fetchModels(entity: User.self)
            // 3. Validate the fetched results
            XCTAssertEqual(fetchedUsers.count, 1)
            XCTAssertEqual(fetchedUsers.first?.id, 1)
            XCTAssertEqual(fetchedUsers.first?.login, "TestUser")
            XCTAssertEqual(fetchedUsers.first?.avatarUrl, "http://example.com/avatar.jpg")
        } catch {
            XCTFail("Fetching models failed with error: \(error)")
        }
    }

    func testFetchOrCreateEntities_FetchesExisting() async throws {
        // Setup: Insert a test entities into the context
        let testUsers = [
            GitHubUser(id: 1, login: "TestUser", avatarUrl: "http://example.com/avatar.png"),
            GitHubUser(id: 2, login: "TestUser2", avatarUrl: "http://example.com/avatar.png")
        ]

        // Convert and cache the test GitHubUsers
        await cacheGitHubUsers(testUsers, in: mockPersistenContainer.viewContext)

        // Attempt to fetch or create entities based on the existinggm GitHubUser
        try await coreDataCacheService.updateOrCreateEntitiesAsync(from: testUsers)

        // Optionally, verify no additional entities were created
        let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
        let results = try mockPersistenContainer.viewContext.fetch(fetchRequest)
        XCTAssertEqual(results.count, 2, "Expected only 2 user in the database")
    }

    // Helper method to cache GitHubUsers into Core Data
    private func cacheGitHubUsers(_ users: [GitHubUser], in context: NSManagedObjectContext) async {
        await context.perform {
            for user in users {
                let newUser = User(context: context)
                newUser.id = Int64(user.id)
                newUser.login = user.login
                newUser.avatarUrl = user.avatarUrl
            }
            do {
                try context.save()
            } catch {
                XCTFail("Failed to save context: \(error)")
            }
        }
    }

    func testUpdateOrCreateEntities_InsertsNewEntities() async throws {
        let context = mockPersistenContainer.newBackgroundContext()

        // Define your GitHubUser entities to insert
        let newGitHubUsers = [
            GitHubUser(id: 1, login: "user1", avatarUrl: "http://example.com/avatar1.jpg"),
            GitHubUser(id: 2, login: "user2", avatarUrl: "http://example.com/avatar2.jpg")
        ]

        // Perform the update or creation operation
        try await coreDataCacheService.updateOrCreateEntitiesAsync(from: newGitHubUsers)

        // Fetch to validate insertion
        let fetchRequest: NSFetchRequest<User> = User.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "id", ascending: true)]

        let results = try context.fetch(fetchRequest)

        // Assert that the entities were inserted correctly
        XCTAssertEqual(results.count, newGitHubUsers.count, "The number of inserted User entities does not match the expected count.")

        for (index, user) in results.enumerated() {
            XCTAssertEqual(user.id, newGitHubUsers[index].uniqueIdentifier as! Int64, "User ID does not match")
            XCTAssertEqual(user.login, newGitHubUsers[index].login, "User login does not match")
            XCTAssertEqual(user.avatarUrl, newGitHubUsers[index].avatarUrl, "User avatar URL does not match")
        }
    }

    func testUpdateOrCreateEntities_UpdatesExistingEntity() async throws {
        // Define the GitHubUser entity with the same ID but different properties to update
        let existingUser =
            GitHubUser(id: 1, login: "originalUser", avatarUrl: "http://example.com/original.jpg")

        try await coreDataCacheService.updateOrCreateEntitiesAsync(from: [existingUser])

        // Define the GitHubUser entity with the same ID but different properties to update
        let updatedGitHubUser =
            GitHubUser(id: 1, login: "updatedUser", avatarUrl: "http://example.com/updated.jpg")


        // Perform the update operation
        try await coreDataCacheService.updateOrCreateEntitiesAsync(from: [updatedGitHubUser])

        // Fetch the updated User entity
        let fetchedModels = try await coreDataCacheService.fetchModels(entity: User.self, predicate: NSPredicate(format: "id == %d", existingUser.id))

        // Validate the update
        XCTAssertEqual(fetchedModels.count, 1, "There should be one User entity with the specified ID.")
        if let updatedUser = fetchedModels.first {
            XCTAssertEqual(updatedUser.login, "updatedUser", "User login should be updated.")
            XCTAssertEqual(updatedUser.avatarUrl, "http://example.com/updated.jpg", "User avatar URL should be updated.")
        } else {
            XCTFail("The User entity was not found.")
        }
    }

    func testUpdateOrCreateEntities_MixedCreateAndUpdate() async throws {
        // Pre-populate the context with an existing User entity to update
        let existingUser = [
            GitHubUser(id: 1, login: "existingUser", avatarUrl: "http://example.com/original.jpg")
        ]

        // Perform the update and create operation
        try await coreDataCacheService.updateOrCreateEntitiesAsync(from: existingUser)

        // Define GitHubUser entities: one matching the existing entity to update, and one new entity to create
        let mixedGitHubUsers = [
            GitHubUser(id: 1, login: "updatedUser", avatarUrl: "http://example.com/updated.jpg"), // This should update the existing entity
            GitHubUser(id: 2, login: "newUser", avatarUrl: "http://example.com/new.jpg") // This should create a new entity
        ]

        // Perform the update and create operation
        try await coreDataCacheService.updateOrCreateEntitiesAsync(from: mixedGitHubUsers)

        // Fetch and validate the results
        let fetchedResults = try await coreDataCacheService.fetchModels(entity: User.self)

        // Validate the expected outcomes
        XCTAssertEqual(fetchedResults.count, 2, "There should be two User entities in total.")

        // Validate each entity
        for user in fetchedResults {
            if user.id == 1 {
                XCTAssertEqual(user.login, "updatedUser", "The existing User entity should be updated.")
            } else if user.id == 2 {
                XCTAssertEqual(user.login, "newUser", "A new User entity should be created.")
            } else {
                XCTFail("Unexpected User entity found.")
            }
        }
    }

    override func tearDown() {
        persistentContainerService = nil
        mockPersistenContainer = nil
        coreDataCacheService = nil
        super.tearDown()
    }
}
