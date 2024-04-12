// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GitHubComponents",
    platforms: [.iOS(.v15)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Users",
            targets: ["Users"]),
        .library(
            name: "Networking",
            targets: ["Networking"]),
        .library(
            name: "Persistence",
            targets: ["Persistence"]),
        .library(
            name: "Services",
            targets: ["Services"]
        ),
        .library(
            name: "ViewModels",
            targets: ["ViewModels"]
        )
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Users",
            path: "Products/Users",
            sources: ["Sources"]),
        .testTarget(
            name: "UsersTests",
            dependencies: ["Users"],
            path: "Tests/Users",
            sources: ["Sources"]),
        .target(
            name: "Networking",
            path: "Products/Networking",
            sources: ["Sources"]
        ),
        .testTarget(
            name: "NetworkingTests",
            dependencies: ["Networking"],
            path: "Tests/Networking",
            sources: ["Sources"]
        ),
        .target(
            name: "Persistence",
            dependencies: ["Networking"],
            path: "Products/Persistence",
            sources: ["Sources"]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: ["Persistence", "Networking"],
            path: "Tests/Persistence",
            sources: ["Sources"]
        ),
        .target(
            name: "Services",
            dependencies: ["Persistence", "Networking"],
            path: "Products/Services",
            sources: ["Sources"]
        ),
        .testTarget(
            name: "ServicesTests",
            dependencies: ["Services"],
            path: "Tests/Services",
            sources: ["Sources"]
        ),
        .target(
            name: "ViewModels",
            dependencies: ["Services"],
            path: "Products/ViewModels",
            sources: ["Sources"]
        )
    ]
)
