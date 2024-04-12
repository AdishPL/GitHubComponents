//
//  File.swift
//  
//
//  Created by Adrian Kaczmarek on 24/02/2024.
//

import CoreData
import Networking

public protocol PersistentContainerProtocol: AnyObject {
    var name: String { get }
    func loadPersistentStores(completionHandler block: @escaping (NSPersistentStoreDescription, Error?) -> Void)
    func setOption(_ option: NSNumber?, forKey key: String)
}

extension NSPersistentContainer: PersistentContainerProtocol {
    public func setOption(_ option: NSNumber?, forKey key: String) {
        self.persistentStoreDescriptions.forEach { $0.setOption(option, forKey: key) }
    }
}

extension User: CoreDataConvertible {
    public typealias NetworkModel = GitHubUser

    public func toNetworkModel() -> GitHubUser {
        return GitHubUser(id: Int64(Int(self.id)), login: self.login ?? "", avatarUrl: self.avatarUrl)
    }
}

public protocol CoreDataConvertible {
    associatedtype NetworkModel: Codable
    func toNetworkModel() -> NetworkModel
}

public class CoreDataCacheService {
    enum CoreDataFetchError: Error {
        case fetchRequestFailed(String)
        case castFailed(String)
    }

    private let persistentContainer: NSPersistentContainer

    public init(persistentContainer: NSPersistentContainer) {
        self.persistentContainer = persistentContainer
    }

    public func fetchModels<T: NSManagedObject & CoreDataConvertible>(entity: T.Type,
                                                                      predicate: NSPredicate? = nil) async throws -> [T.NetworkModel] {
        let context = persistentContainer.viewContext
        let request = T.fetchRequest()
        request.predicate = predicate
        let sortDescriptor = NSSortDescriptor(key: "id", ascending: true)
        request.sortDescriptors = [sortDescriptor]
        
        let fetchedObjects = try await context.perform {
            do {
                let fetchResult = try context.fetch(request)
                guard let typedResult = fetchResult as? [T] else {
                    throw CoreDataFetchError.castFailed("Failed to cast fetch result to expected type [\(T.self)].")
                }
                return typedResult
            } catch {
                throw CoreDataFetchError.fetchRequestFailed("Failed to fetch or convert models: \(error.localizedDescription)")
            }
        }
        return fetchedObjects.map { $0.toNetworkModel() }
    }

    public func updateOrCreateEntitiesAsync<M: ModelConvertible>(
        from models: [M],
        withAdditionalContext context: [String: Any]? = nil,
        modifyEntity: ((M.Entity, [String: Any]?) -> Void)? = nil
    ) async throws {

        guard !models.isEmpty else { return }
        let backgroundContext = persistentContainer.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        try await withThrowingTaskGroup(of: Void.self) { group in // Concurrent group

            for model in models {
                group.addTask { [weak self] in
                    guard let self = self else { return }
                    do {
                        let entity = try await self.fetchOrCreateEntityAsync(from: model, in: backgroundContext)
                        modifyEntity?(entity, context)
                        model.updateEntity(entity: entity)
                    } catch {
                        print("Error updating or creating entity: \(error)")
                    }
                }
            }

            try await group.waitForAll() // Wait for all tasks
        }

        if backgroundContext.hasChanges {
            try await backgroundContext.perform { // If set up for background saving
                try backgroundContext.save()
            }
        }
    }

    private func fetchOrCreateEntity<M: ModelConvertible>(from model: M, in context: NSManagedObjectContext) throws -> M.Entity {
        let fetchRequest = M.Entity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %d", model.uniqueIdentifier as! CVarArg)

        let results = try context.fetch(fetchRequest)
        let entity: M.Entity
        if let existingEntity = results.first as? M.Entity {
            entity = existingEntity
        } else {
            entity = M.Entity(context: context)
        }

        return entity
    }

    private func fetchOrCreateEntityAsync<M: ModelConvertible>(from model: M, in context: NSManagedObjectContext) async throws -> M.Entity {
        return try await context.performAndWait {
            try fetchOrCreateEntity(from: model, in: context)
        }
    }
}

public protocol ModelConvertible {
    associatedtype Entity: NSManagedObject
    var uniqueIdentifier: Any { get }
    func updateEntity(entity: Entity)
}

extension GitHubUser: ModelConvertible {
    public typealias Entity = User

    public var uniqueIdentifier: Any {
        return id
    }

    public func updateEntity(entity: User) {
        entity.id = Int64(self.id)
        entity.login = self.login
        entity.avatarUrl = self.avatarUrl
    }
}

extension NSManagedObjectContext {
    func performAndWait<T>(_ block: () throws -> T) async throws -> T {
        return try await withCheckedThrowingContinuation { continuation in
            performAndWait {
                do {
                    let result = try block()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
