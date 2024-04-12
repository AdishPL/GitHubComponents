//
//  File.swift
//  
//
//  Created by Adrian Kaczmarek on 24/02/2024.
//

import CoreData

public let PersistenceModuleBundle = Bundle.module

private class PersistenceModule { }

protocol PersistentContainerFactoryProtocol {
    func createContainer(named name: String) -> PersistentContainerProtocol
}

class PersistentContainerFactory: PersistentContainerFactoryProtocol {
    func createContainer(named name: String) -> PersistentContainerProtocol {
        guard let modelURL = PersistenceModuleBundle.url(forResource: name, withExtension: "momd"),
              let mom = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Unable to locate or load the managed object model")
        }
        return NSPersistentContainer(name: name, managedObjectModel: mom)
    }
}

public final class PersistentContainerService {
    public enum CoreDataModel: String {
        case GithubUsersList

        var modelName: String {
            return self.rawValue
        }
    }

    private let containerFactory: PersistentContainerFactoryProtocol

    public static let shared = PersistentContainerService()

    private var containers: [CoreDataModel: PersistentContainerProtocol] = [:]

    init(containerFactory: PersistentContainerFactoryProtocol = PersistentContainerFactory()) {
        self.containerFactory = containerFactory
    }

    public func container(forModel model: CoreDataModel,
                          shouldMigrateAutomatically: Bool = true,
                          shouldInferMappingModelAutomatically: Bool = true) -> PersistentContainerProtocol {
        if let container = containers[model] {
            // Return the existing container if already initialized
            return container
        } else {
            // Create and configure a new container for the model
            let container = containerFactory.createContainer(named: model.modelName)
            if shouldMigrateAutomatically || shouldInferMappingModelAutomatically {
                let options = [NSMigratePersistentStoresAutomaticallyOption: shouldMigrateAutomatically,
                                     NSInferMappingModelAutomaticallyOption: shouldInferMappingModelAutomatically]
                options.forEach { key, value in
                    container.setOption(value as NSNumber, forKey: key)
                }
            }
            
            container.loadPersistentStores { _, error in
                if let error = error as NSError? {
                    fatalError("Unresolved error \(error), \(error.userInfo)")
                }
            }

            containers[model] = container
            return container
        }
    }
}
