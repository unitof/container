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
import ContainerizationError
import Darwin
import Dispatch
import Foundation

extension Application {
    struct ContainerLogs: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "logs",
            abstract: "Fetch container stdio or boot logs"
        )

        @OptionGroup
        var global: Flags.Global

        @Flag(name: .shortAndLong, help: "Follow log output")
        var follow: Bool = false

        @Flag(name: .long, help: "Display the boot log for the container instead of stdio")
        var boot: Bool = false

        @Option(name: [.customShort("n")], help: "Number of lines to show from the end of the logs. If not provided this will print all of the logs")
        var numLines: Int?

        @Argument(help: "Container to fetch logs for")
        var container: String

        func run() async throws {
            do {
                let container = try await ClientContainer.get(id: container)
                let fhs = try await container.logs()
                let fileHandle = boot ? fhs[1] : fhs[0]

                try await Self.tail(
                    fh: fileHandle,
                    n: numLines,
                    follow: follow
                )
            } catch {
                throw ContainerizationError(
                    .invalidArgument,
                    message: "failed to fetch container logs for \(container): \(error)"
                )
            }
        }

        private static func tail(
            fh: FileHandle,
            n: Int?,
            follow: Bool
        ) async throws {
            if let n {
                var buffer = Data()
                let size = try fh.seekToEnd()
                var offset = size
                var lines: [String] = []

                while offset > 0, lines.count < n {
                    let readSize = min(1024, offset)
                    offset -= readSize
                    try fh.seek(toOffset: offset)

                    let data = fh.readData(ofLength: Int(readSize))
                    buffer.insert(contentsOf: data, at: 0)

                    if let chunk = String(data: buffer, encoding: .utf8) {
                        lines = chunk.components(separatedBy: .newlines)
                        lines = lines.filter { !$0.isEmpty }
                    }
                }

                lines = Array(lines.suffix(n))
                for line in lines {
                    print(line)
                }
            } else {
                // Fast path if all they want is the full file.
                guard let data = try fh.readToEnd() else {
                    // Seems you get nil if it's a zero byte read, or you
                    // try and read from dev/null.
                    return
                }
                guard let str = String(data: data, encoding: .utf8) else {
                    throw ContainerizationError(
                        .internalError,
                        message: "failed to convert container logs to utf8"
                    )
                }
                print(str.trimmingCharacters(in: .newlines))
            }

            fflush(stdout)
            if follow {
                setbuf(stdout, nil)
                try await Self.followFile(fh: fh)
            }
        }

        private static func followFile(fh: FileHandle) async throws {
            _ = try fh.seekToEnd()
            let stream = AsyncStream<String> { cont in
                fh.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        // Triggers on container restart - can exit here as well
                        do {
                            _ = try fh.seekToEnd()  // To continue streaming existing truncated log files
                        } catch {
                            fh.readabilityHandler = nil
                            cont.finish()
                            return
                        }
                    }
                    if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                        var lines = str.components(separatedBy: .newlines)
                        lines = lines.filter { !$0.isEmpty }
                        for line in lines {
                            cont.yield(line)
                        }
                    }
                }
            }

            for await line in stream {
                print(line)
            }
        }
    }
}
