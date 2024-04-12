//
//  ContentView.swift
//  GitHubUsers
//
//  Created by Adrian Kaczmarek on 04/04/2024.
//

import SwiftUI
import ViewModels
import Networking

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

struct GitHubUsersListView: View {
    @StateObject var viewModel = UsersViewModel()

    var body: some View {
        NavigationView {
            VStack {
                switch viewModel.state {
                case .idle:
                    Text("Enter a query to begin")
                case .loading:
                    ProgressView()
                case .cached(let users):
                    UsersList(users: users) // Your custom view to list users
                    Text("Updating...")
                        .font(.caption)
                        .foregroundColor(.gray)
                case .loaded(let users):
                    UsersList(users: users)
                case .empty:
                    Text("No results found")
                case .failed(let error):
                    Text("Error: \(error.localizedDescription)")
                }
            }
        }
        .searchable(text: $viewModel.searchText)
    }
}

struct UsersList: View {
    var users: [GitHubUser]

    var body: some View {
        List(users, id: \.id) { user in
            Text(user.login)
        }
    }
}
