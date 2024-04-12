//
//  File.swift
//  
//
//  Created by Adrian Kaczmarek on 03/03/2024.
//

import Network
import Persistence
import Networking
import CoreData
import Combine

public protocol GitHubUsersProvidable {
    func fetchCachedUsers(matching query: String) async throws -> [GitHubUser]
    func fetchAndSaveUsersFromEndpoint(matching query: String) async throws -> [GitHubUser]
}

public final class CoreDataUserService: GitHubUsersProvidable {
    private let gitHubService: GitHubService
    private let coreDataCacheService: CoreDataCacheService
    private let networkMonitor: NetworkMonitoring

    // Publishers
    @Published public private(set) var fetchedUsers: [GitHubUser] = []

    private var cancellables = Set<AnyCancellable>()

    public init(gitHubService: GitHubService = GitHubService(),
                coreDataCacheService: CoreDataCacheService? = nil,
                networkMonitor: NetworkMonitoring = NetworkMonitor()) {
        self.gitHubService = gitHubService
        self.networkMonitor = networkMonitor
        
        if let coreDataCacheService = coreDataCacheService {
            self.coreDataCacheService = coreDataCacheService
        } else {
            if let container = PersistentContainerService.shared.container(forModel: .GithubUsersList) as? NSPersistentContainer {
                self.coreDataCacheService = CoreDataCacheService(persistentContainer: container)
            } else {
                fatalError("Could not initialize NSPersistentContainer")
            }
        }
        networkMonitor.startMonitoring()
    }

    public func fetchCachedUsers(matching query: String) async throws -> [GitHubUser] {
        guard !query.isEmpty else {
            return []
        }

        let predicate = NSPredicate(format: "query ==[cd] %@", query)
        return try await coreDataCacheService.fetchModels(entity: User.self, predicate: predicate)
    }

    public func fetchAndSaveUsersFromEndpoint(matching query: String) async throws -> [GitHubUser] {
        guard !query.isEmpty, networkMonitor.isConnected else {
            return []
        }

        let fetchedUsers = try await gitHubService.fetchUsers(query: query)
        try await coreDataCacheService.updateOrCreateEntitiesAsync(from: fetchedUsers,
                                                                   withAdditionalContext: ["query": query]) { (entity: User, context) in
            if let query = context?["query"] as? String {
                entity.query = query
            }
        }
        return fetchedUsers
    }
}
