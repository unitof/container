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
import Containerization
import ContainerizationError
import ContainerizationExtras
import ContainerizationOS
import Foundation
import NIOCore
import NIOPosix
import TerminalProgress

extension Application {
    struct ContainerRunCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "run",
            abstract: "Run a container")

        @OptionGroup
        var processFlags: Flags.Process

        @OptionGroup
        var resourceFlags: Flags.Resource

        @OptionGroup
        var managementFlags: Flags.Management

        @OptionGroup
        var registryFlags: Flags.Registry

        @OptionGroup
        var global: Flags.Global

        @OptionGroup
        var progressFlags: Flags.Progress

        @Argument(help: "Image name")
        var image: String

        @Argument(parsing: .captureForPassthrough, help: "Container init process arguments")
        var arguments: [String] = []

        func run() async throws {
            var exitCode: Int32 = 127
            let id = Utility.createContainerID(name: self.managementFlags.name)

            var progressConfig: ProgressConfig
            if progressFlags.disableProgressUpdates {
                progressConfig = try ProgressConfig(disableProgressUpdates: progressFlags.disableProgressUpdates)
            } else {
                progressConfig = try ProgressConfig(
                    showTasks: true,
                    showItems: true,
                    ignoreSmallSize: true,
                    totalTasks: 6
                )
            }

            let progress = ProgressBar(config: progressConfig)
            defer {
                progress.finish()
            }
            progress.start()

            try Utility.validEntityName(id)

            // Check if container with id already exists.
            let existing = try? await ClientContainer.get(id: id)
            guard existing == nil else {
                throw ContainerizationError(
                    .exists,
                    message: "container with id \(id) already exists"
                )
            }

            let ck = try await Utility.containerConfigFromFlags(
                id: id,
                image: image,
                arguments: arguments,
                process: processFlags,
                management: managementFlags,
                resource: resourceFlags,
                registry: registryFlags,
                progressUpdate: progress.handler
            )

            progress.set(description: "Starting container")

            let options = ContainerCreateOptions(autoRemove: managementFlags.remove)
            let container = try await ClientContainer.create(
                configuration: ck.0,
                options: options,
                kernel: ck.1
            )

            let detach = self.managementFlags.detach

            do {
                let io = try ProcessIO.create(
                    tty: self.processFlags.tty,
                    interactive: self.processFlags.interactive,
                    detach: detach
                )

                let process = try await container.bootstrap(stdio: io.stdio)
                progress.finish()

                if !self.managementFlags.cidfile.isEmpty {
                    let path = self.managementFlags.cidfile
                    let data = id.data(using: .utf8)
                    var attributes = [FileAttributeKey: Any]()
                    attributes[.posixPermissions] = 0o644
                    let success = FileManager.default.createFile(
                        atPath: path,
                        contents: data,
                        attributes: attributes
                    )
                    guard success else {
                        throw ContainerizationError(
                            .internalError, message: "failed to create cidfile at \(path): \(errno)")
                    }
                }

                if detach {
                    try await process.start()
                    defer {
                        try? io.close()
                    }
                    try io.closeAfterStart()
                    print(id)
                    return
                }

                if !self.processFlags.tty {
                    var handler = SignalThreshold(threshold: 3, signals: [SIGINT, SIGTERM])
                    handler.start {
                        print("Received 3 SIGINT/SIGTERM's, forcefully exiting.")
                        Darwin.exit(1)
                    }
                }

                exitCode = try await Application.handleProcess(io: io, process: process)
            } catch {
                if error is ContainerizationError {
                    throw error
                }
                throw ContainerizationError(.internalError, message: "failed to run container: \(error)")
            }
            throw ArgumentParser.ExitCode(exitCode)
        }
    }
}

struct ProcessIO {
    let stdin: Pipe?
    let stdout: Pipe?
    let stderr: Pipe?
    var ioTracker: IoTracker?

    struct IoTracker {
        let stream: AsyncStream<Void>
        let cont: AsyncStream<Void>.Continuation
        let configuredStreams: Int
    }

    let stdio: [FileHandle?]

    let console: Terminal?

    func closeAfterStart() throws {
        try stdin?.fileHandleForReading.close()
        try stdout?.fileHandleForWriting.close()
        try stderr?.fileHandleForWriting.close()
    }

    func close() throws {
        try console?.reset()
    }

    static func create(tty: Bool, interactive: Bool, detach: Bool) throws -> ProcessIO {
        let current: Terminal? = try {
            if !tty || !interactive {
                return nil
            }
            let current = try Terminal.current
            try current.setraw()
            return current
        }()

        var stdio = [FileHandle?](repeating: nil, count: 3)

        let stdin: Pipe? = {
            if !interactive && !tty {
                return nil
            }
            return Pipe()
        }()

        if let stdin {
            if interactive {
                let pin = FileHandle.standardInput
                let stdinOSFile = OSFile(fd: pin.fileDescriptor)
                let pipeOSFile = OSFile(fd: stdin.fileHandleForWriting.fileDescriptor)
                try stdinOSFile.makeNonBlocking()
                nonisolated(unsafe) let buf = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: Int(getpagesize()))

                pin.readabilityHandler = { _ in
                    Self.streamStdin(
                        from: stdinOSFile,
                        to: pipeOSFile,
                        buffer: buf,
                    ) {
                        pin.readabilityHandler = nil
                        buf.deallocate()
                        try? stdin.fileHandleForWriting.close()
                    }
                }
            }
            stdio[0] = stdin.fileHandleForReading
        }

        let stdout: Pipe? = {
            if detach {
                return nil
            }
            return Pipe()
        }()

        var configuredStreams = 0
        let (stream, cc) = AsyncStream<Void>.makeStream()
        if let stdout {
            configuredStreams += 1
            let pout: FileHandle = {
                if let current {
                    return current.handle
                }
                return .standardOutput
            }()

            let rout = stdout.fileHandleForReading
            rout.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    rout.readabilityHandler = nil
                    cc.yield()
                    return
                }
                try! pout.write(contentsOf: data)
            }
            stdio[1] = stdout.fileHandleForWriting
        }

        let stderr: Pipe? = {
            if detach || tty {
                return nil
            }
            return Pipe()
        }()
        if let stderr {
            configuredStreams += 1
            let perr: FileHandle = .standardError
            let rerr = stderr.fileHandleForReading
            rerr.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    rerr.readabilityHandler = nil
                    cc.yield()
                    return
                }
                try! perr.write(contentsOf: data)
            }
            stdio[2] = stderr.fileHandleForWriting
        }

        var ioTracker: IoTracker? = nil
        if configuredStreams > 0 {
            ioTracker = .init(stream: stream, cont: cc, configuredStreams: configuredStreams)
        }

        return .init(
            stdin: stdin,
            stdout: stdout,
            stderr: stderr,
            ioTracker: ioTracker,
            stdio: stdio,
            console: current
        )
    }

    static func streamStdin(
        from: OSFile,
        to: OSFile,
        buffer: UnsafeMutableBufferPointer<UInt8>,
        onErrorOrEOF: () -> Void,
    ) {
        while true {
            let (bytesRead, action) = from.read(buffer)
            if bytesRead > 0 {
                let view = UnsafeMutableBufferPointer(
                    start: buffer.baseAddress,
                    count: bytesRead
                )

                let (bytesWritten, _) = to.write(view)
                if bytesWritten != bytesRead {
                    onErrorOrEOF()
                    return
                }
            }

            switch action {
            case .error(_), .eof, .brokenPipe:
                onErrorOrEOF()
                return
            case .again:
                return
            case .success:
                break
            }
        }
    }

    public func wait() async throws {
        guard let ioTracker = self.ioTracker else {
            return
        }
        do {
            try await Timeout.run(seconds: 3) {
                var counter = ioTracker.configuredStreams
                for await _ in ioTracker.stream {
                    counter -= 1
                    if counter == 0 {
                        ioTracker.cont.finish()
                        break
                    }
                }
            }
        } catch {
            log.error("Timeout waiting for IO to complete : \(error)")
            throw error
        }
    }
}

struct OSFile: Sendable {
    private let fd: Int32

    enum IOAction: Equatable {
        case eof
        case again
        case success
        case brokenPipe
        case error(_ errno: Int32)
    }

    init(fd: Int32) {
        self.fd = fd
    }

    init(handle: FileHandle) {
        self.fd = handle.fileDescriptor
    }

    func makeNonBlocking() throws {
        let flags = fcntl(fd, F_GETFL)
        guard flags != -1 else {
            throw POSIXError.fromErrno()
        }

        if fcntl(fd, F_SETFL, flags | O_NONBLOCK) == -1 {
            throw POSIXError.fromErrno()
        }
    }

    func write(_ buffer: UnsafeMutableBufferPointer<UInt8>) -> (wrote: Int, action: IOAction) {
        if buffer.count == 0 {
            return (0, .success)
        }

        var bytesWrote: Int = 0
        while true {
            let n = Darwin.write(
                self.fd,
                buffer.baseAddress!.advanced(by: bytesWrote),
                buffer.count - bytesWrote
            )
            if n == -1 {
                if errno == EAGAIN || errno == EIO {
                    return (bytesWrote, .again)
                }
                return (bytesWrote, .error(errno))
            }

            if n == 0 {
                return (bytesWrote, .brokenPipe)
            }

            bytesWrote += n
            if bytesWrote < buffer.count {
                continue
            }
            return (bytesWrote, .success)
        }
    }

    func read(_ buffer: UnsafeMutableBufferPointer<UInt8>) -> (read: Int, action: IOAction) {
        if buffer.count == 0 {
            return (0, .success)
        }

        var bytesRead: Int = 0
        while true {
            let n = Darwin.read(
                self.fd,
                buffer.baseAddress!.advanced(by: bytesRead),
                buffer.count - bytesRead
            )
            if n == -1 {
                if errno == EAGAIN || errno == EIO {
                    return (bytesRead, .again)
                }
                return (bytesRead, .error(errno))
            }

            if n == 0 {
                return (bytesRead, .eof)
            }

            bytesRead += n
            if bytesRead < buffer.count {
                continue
            }
            return (bytesRead, .success)
        }
    }
}
