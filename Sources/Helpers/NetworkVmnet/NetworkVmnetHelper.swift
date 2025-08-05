//===----------------------------------------------------------------------===//
// Copyright © 2025 Apple Inc. and the container project authors. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

import ArgumentParser
import CVersion
import ContainerLog
import ContainerNetworkService
import ContainerXPC
import ContainerizationExtras
import Foundation
import Logging

@main
struct NetworkVmnetHelper: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "container-network-vmnet",
        abstract: "XPC service for managing a vmnet network",
        version: releaseVersion(),
        subcommands: [
            Start.self
        ]
    )
}

extension NetworkVmnetHelper {
    struct Start: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "start",
            abstract: "Starts the network plugin"
        )

        @Flag(name: .long, help: "Enable debug logging")
        var debug = false

        @Option(name: .long, help: "XPC service identifier")
        var serviceIdentifier: String

        @Option(name: .shortAndLong, help: "Network identifier")
        var id: String

        @Option(name: .shortAndLong, help: "CIDR address for the subnet")
        var subnet: String?

        func run() async throws {
            let commandName = NetworkVmnetHelper._commandName
            let log = setupLogger()
            log.info("starting \(commandName)")
            defer {
                log.info("stopping \(commandName)")
            }

            do {
                log.info("configuring XPC server")
                let subnet = try self.subnet.map { try CIDRAddress($0) }
                let configuration = NetworkConfiguration(id: id, mode: .nat, subnet: subnet?.description)
                let network = try Self.createNetwork(configuration: configuration, log: log)
                try await network.start()
                let server = try await NetworkService(network: network, log: log)
                let xpc = XPCServer(
                    identifier: serviceIdentifier,
                    routes: [
                        NetworkRoutes.state.rawValue: server.state,
                        NetworkRoutes.allocate.rawValue: server.allocate,
                        NetworkRoutes.deallocate.rawValue: server.deallocate,
                        NetworkRoutes.lookup.rawValue: server.lookup,
                        NetworkRoutes.disableAllocator.rawValue: server.disableAllocator,
                    ],
                    log: log
                )

                log.info("starting XPC server")
                try await xpc.listen()
            } catch {
                log.error("\(commandName) failed", metadata: ["error": "\(error)"])
                NetworkVmnetHelper.exit(withError: error)
            }
        }

        private func setupLogger() -> Logger {
            LoggingSystem.bootstrap { label in
                OSLogHandler(
                    label: label,
                    category: "NetworkVmnetHelper"
                )
            }
            var log = Logger(label: "com.apple.container")
            if debug {
                log.logLevel = .debug
            }
            log[metadataKey: "id"] = "\(id)"
            return log
        }

        private static func createNetwork(configuration: NetworkConfiguration, log: Logger) throws -> Network {
            guard #available(macOS 26, *) else {
                return try AllocationOnlyVmnetNetwork(configuration: configuration, log: log)
            }

            return try ReservedVmnetNetwork(configuration: configuration, log: log)
        }
    }

    private static func releaseVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? get_release_version().map { String(cString: $0) } ?? "0.0.0"
    }
}
