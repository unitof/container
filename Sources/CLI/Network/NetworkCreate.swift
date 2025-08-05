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
import ContainerClient
import ContainerNetworkService
import ContainerizationError
import Foundation
import TerminalProgress

extension Application {
    struct NetworkCreate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create a new network")

        @Argument(help: "Network name")
        var name: String

        @OptionGroup
        var global: Flags.Global

        func run() async throws {
            let config = NetworkConfiguration(id: self.name, mode: .nat)
            let state = try await ClientNetwork.create(configuration: config)
            print(state.id)
        }
    }
}
