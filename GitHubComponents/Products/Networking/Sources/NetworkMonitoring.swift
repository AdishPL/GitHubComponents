//
//  NetworkMonitoring.swift
//
//
//  Created by Adrian Kaczmarek on 10/03/2024.
//

import Network

public protocol NetworkMonitoring {
    var isConnected: Bool { get set }
    func startMonitoring()
    func stopMonitoring()
}

public class NetworkMonitor: NetworkMonitoring {
    private let pathMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    public var isConnected: Bool = false

    public init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = path.status == .satisfied
        }
    }

    public func startMonitoring() {
        pathMonitor.start(queue: queue)
    }

    public func stopMonitoring() {
        pathMonitor.cancel()
    }
}
