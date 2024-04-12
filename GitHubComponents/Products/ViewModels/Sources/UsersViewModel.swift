//
//  UsersViewModel.swift
//
//
//  Created by Adrian Kaczmarek on 04/04/2024.
//

import SwiftUI
import Combine
import Services
import Networking

public enum DataState<T> {
    case idle
    case loading
    case cached(T)
    case loaded(T)
    case empty
    case failed(Error)

    var isIdle: Bool {
        if case .idle = self {
            return true
        }
        return false
    }

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var isEmpty: Bool {
        if case .empty = self {
            return true
        }
        return false
    }

    var isCached: Bool {
        if case .cached(let t) = self {
            return true
        }
        return false
    }
}

@MainActor
public final class UsersViewModel: ObservableObject {
    private let searchQueue = DispatchQueue(label: "SearchQueue")
    private var subscriptions = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>? // Track the ongoing search task

    @Published public var state: DataState<[GitHubUser]> = .idle
    @Published public var searchText = ""

    private var userService: GitHubUsersProvidable

    public init(userService: GitHubUsersProvidable = CoreDataUserService()) {
        self.userService = userService
        setupSearchPipeline()
    }

    private func fetchUsers(matching query: String) {
        searchTask?.cancel() // Cancel any ongoing task

        guard !query.isEmpty else {
            state = .empty
            return
        }

        // Initially mark as loading to cover the scenario of no cache available
        state = .loading

        // Fetch cached users for an immediate UI update
        searchTask = Task {
            let cachedUsers = try? await userService.fetchCachedUsers(matching: query)
            if let cachedUsers, !cachedUsers.isEmpty {
                state = .cached(cachedUsers)
            }
            
            // Proceed with fetching from the network
            do {
                let fetchedUsers = try await userService.fetchAndSaveUsersFromEndpoint(matching: query)
                if fetchedUsers.isEmpty, state.isLoading {
                    state = .empty
                } else {
                    state = .loaded(fetchedUsers)
                }
            } catch {
                // Transition to failed state only if no cached users were shown
                if state.isLoading {
                    state = .failed(error)
                }
            }
        }
    }

    private func setupSearchPipeline() {
        $searchText
            .debounce(for: .seconds(0.5), scheduler: searchQueue) // Adjust delay as needed
            .removeDuplicates()
            .filter { [weak self] text in
                guard !text.isEmpty else {
                    self?.state = .idle
                    return false
                }

                return true
            }
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: { [weak self] text in
                self?.fetchUsers(matching: text)
            })
            .store(in: &subscriptions)
    }

}
