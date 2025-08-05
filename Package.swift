// swift-tools-version: 6.2
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

// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let releaseVersion = ProcessInfo.processInfo.environment["RELEASE_VERSION"] ?? "0.0.0"
let gitCommit = ProcessInfo.processInfo.environment["GIT_COMMIT"] ?? "unspecified"
let scVersion = "0.5.0"
let builderShimVersion = "0.6.0"

let package = Package(
    name: "container",
    platforms: [.macOS("15")],
    products: [
        .library(name: "ContainerSandboxService", targets: ["ContainerSandboxService"]),
        .library(name: "ContainerNetworkService", targets: ["ContainerNetworkService"]),
        .library(name: "ContainerImagesService", targets: ["ContainerImagesService", "ContainerImagesServiceClient"]),
        .library(name: "ContainerClient", targets: ["ContainerClient"]),
        .library(name: "ContainerBuild", targets: ["ContainerBuild"]),
        .library(name: "ContainerLog", targets: ["ContainerLog"]),
        .library(name: "ContainerPersistence", targets: ["ContainerPersistence"]),
        .library(name: "ContainerPlugin", targets: ["ContainerPlugin"]),
        .library(name: "ContainerXPC", targets: ["ContainerXPC"]),
        .library(name: "SocketForwarder", targets: ["SocketForwarder"]),
        .library(name: "ContainerBuildReporting", targets: ["ContainerBuildReporting"]),
        .library(name: "ContainerBuildIR", targets: ["ContainerBuildIR"]),
        .library(name: "ContainerBuildExecutor", targets: ["ContainerBuildExecutor"]),
        .library(name: "ContainerBuildCache", targets: ["ContainerBuildCache"]),
        .library(name: "ContainerBuildSnapshotter", targets: ["ContainerBuildSnapshotter"]),
        .library(name: "ContainerBuildDiffer", targets: ["ContainerBuildDiffer"]),
        .library(name: "ContainerBuildParser", targets: ["ContainerBuildParser"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.26.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.29.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.80.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin.git", from: "1.1.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.20.1"),
        .package(url: "https://github.com/orlandos-nl/DNSClient.git", from: "2.4.1"),
        .package(url: "https://github.com/Bouke/DNS.git", from: "1.2.0"),
        .package(url: "https://github.com/apple/containerization.git", exact: Version(stringLiteral: scVersion)),
    ],
    targets: [
        .executableTarget(
            name: "container",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "Containerization", package: "containerization"),
                .product(name: "ContainerizationOCI", package: "containerization"),
                .product(name: "ContainerizationOS", package: "containerization"),
                "CVersion",
                "TerminalProgress",
                "ContainerBuild",
                "ContainerClient",
                "ContainerPlugin",
                "ContainerLog",
            ],
            path: "Sources/CLI"
        ),
        .executableTarget(
            name: "container-apiserver",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Containerization", package: "containerization"),
                .product(name: "ContainerizationExtras", package: "containerization"),
                .product(name: "ContainerizationOS", package: "containerization"),
                "CVersion",
                "DNSServer",
                "ContainerNetworkService",
                "ContainerSandboxService",
                "ContainerClient",
                "ContainerLog",
                "ContainerPersistence",
                "ContainerPlugin",
            ],
            path: "Sources/APIServer"
        ),
        .executableTarget(
            name: "container-runtime-linux",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "Containerization", package: "containerization"),
                "CVersion",
                "ContainerNetworkService",
                "ContainerSandboxService",
                "ContainerLog",
                "ContainerXPC",
            ],
            path: "Sources/Helpers/RuntimeLinux"
        ),
        .target(
            name: "ContainerSandboxService",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Containerization", package: "containerization"),
                .product(name: "ContainerizationOS", package: "containerization"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "ContainerNetworkService",
                "ContainerClient",
                "ContainerXPC",
                "SocketForwarder",
            ],
            path: "Sources/Services/ContainerSandboxService"
        ),
        .executableTarget(
            name: "container-network-vmnet",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Containerization", package: "containerization"),
                .product(name: "ContainerizationExtras", package: "containerization"),
                .product(name: "ContainerizationIO", package: "containerization"),
                .product(name: "ContainerizationOS", package: "containerization"),
                "CVersion",
                "ContainerNetworkService",
                "ContainerLog",
                "ContainerXPC",
            ],
            path: "Sources/Helpers/NetworkVmnet"
        ),
        .target(
            name: "ContainerNetworkService",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Containerization", package: "containerization"),
                .product(name: "ContainerizationOS", package: "containerization"),
                "ContainerXPC",
            ],
            path: "Sources/Services/ContainerNetworkService"
        ),
        .executableTarget(
            name: "container-core-images",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Containerization", package: "containerization"),
                "CVersion",
                "ContainerLog",
                "ContainerXPC",
                "ContainerImagesService",
            ],
            path: "Sources/Helpers/Images"
        ),
        .target(
            name: "ContainerImagesService",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Containerization", package: "containerization"),
                "ContainerXPC",
                "ContainerLog",
                "ContainerClient",
                "ContainerImagesServiceClient",
            ],
            path: "Sources/Services/ContainerImagesService/Server"
        ),
        .target(
            name: "ContainerImagesServiceClient",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Containerization", package: "containerization"),
                "ContainerXPC",
                "ContainerLog",
            ],
            path: "Sources/Services/ContainerImagesService/Client"
        ),
        .target(
            name: "ContainerBuild",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "Containerization", package: "containerization"),
                .product(name: "ContainerizationArchive", package: "containerization"),
                .product(name: "ContainerizationOCI", package: "containerization"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "ContainerClient",
            ]
        ),
        .testTarget(
            name: "ContainerBuildTests",
            dependencies: [
                "ContainerBuild"
            ]
        ),
        .target(
            name: "ContainerClient",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Containerization", package: "containerization"),
                .product(name: "ContainerizationOCI", package: "containerization"),
                .product(name: "ContainerizationOS", package: "containerization"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "ContainerNetworkService",
                "ContainerImagesServiceClient",
                "TerminalProgress",
                "ContainerXPC",
                "CVersion",
            ]
        ),
        .testTarget(
            name: "ContainerClientTests",
            dependencies: [
                .product(name: "Containerization", package: "containerization"),
                "ContainerClient",
            ]
        ),
        .executableTarget(
            name: "native-builder-demo",
            dependencies: ["ContainerBuildIR", "ContainerBuildExecutor", "ContainerBuildCache"],
            path: "Sources/NativeBuilder/ContainerBuildDemo"
        ),
        .target(
            name: "ContainerBuildReporting",
            dependencies: [],
            path: "Sources/NativeBuilder/ContainerBuildReporting",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "ContainerBuildIR",
            dependencies: [
                "ContainerBuildReporting",
                .product(name: "ContainerizationOCI", package: "containerization"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Sources/NativeBuilder/ContainerBuildIR",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ],
        ),
        .target(
            name: "ContainerBuildExecutor",
            dependencies: [
                "ContainerBuildReporting",
                "ContainerBuildIR",
                "ContainerBuildSnapshotter",
                "ContainerBuildCache",
                .product(name: "ContainerizationOCI", package: "containerization"),
            ],
            path: "Sources/NativeBuilder/ContainerBuildExecutor",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "ContainerBuildCache",
            dependencies: [
                "ContainerBuildIR",
                "ContainerBuildSnapshotter",
                .product(name: "ContainerizationOCI", package: "containerization"),
                .product(name: "ContainerizationExtras", package: "containerization"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Sources/NativeBuilder/ContainerBuildCache",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "ContainerBuildSnapshotter",
            dependencies: ["ContainerBuildIR"],
            path: "Sources/NativeBuilder/ContainerBuildSnapshotter",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "ContainerBuildDiffer",
            dependencies: [
                "ContainerBuildIR",
                "ContainerBuildSnapshotter",
            ],
            path: "Sources/NativeBuilder/ContainerBuildDiffer",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "ContainerBuildParser",
            dependencies: [
                "ContainerBuildIR"
            ],
            path: "Sources/NativeBuilder/ContainerBuildParser",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "NativeBuilderTests",
            dependencies: [
                "ContainerBuildIR",
                "ContainerBuildExecutor",
                "ContainerBuildCache",
                "ContainerBuildReporting",
                "ContainerBuildParser",
            ]
        ),
        .target(
            name: "ContainerPersistence",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Containerization", package: "containerization"),
            ]
        ),
        .target(
            name: "ContainerPlugin",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ContainerizationOS", package: "containerization"),
            ]
        ),
        .testTarget(
            name: "ContainerPluginTests",
            dependencies: [
                "ContainerPlugin"
            ]
        ),
        .target(
            name: "ContainerLog",
            dependencies: [
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .target(
            name: "ContainerXPC",
            dependencies: [
                .product(name: "ContainerizationExtras", package: "containerization"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "TerminalProgress",
            dependencies: [
                .product(name: "ContainerizationOS", package: "containerization")
            ]
        ),
        .testTarget(
            name: "TerminalProgressTests",
            dependencies: ["TerminalProgress"]
        ),
        .target(
            name: "DNSServer",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "DNSClient", package: "DNSClient"),
                .product(name: "DNS", package: "DNS"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(
            name: "DNSServerTests",
            dependencies: [
                .product(name: "DNS", package: "DNS"),
                "DNSServer",
            ]
        ),
        .target(
            name: "SocketForwarder",
            dependencies: [
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
            ]
        ),
        .testTarget(
            name: "SocketForwarderTests",
            dependencies: ["SocketForwarder"]
        ),
        .testTarget(
            name: "CLITests",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Containerization", package: "containerization"),
                .product(name: "ContainerizationExtras", package: "containerization"),
                .product(name: "ContainerizationOS", package: "containerization"),
                "ContainerBuild",
                "ContainerClient",
                "ContainerNetworkService",
            ],
            path: "Tests/CLITests"
        ),
        .target(
            name: "CVersion",
            dependencies: [],
            publicHeadersPath: "include",
            cSettings: [
                .define("CZ_VERSION", to: "\"\(scVersion)\""),
                .define("GIT_COMMIT", to: "\"\(gitCommit)\""),
                .define("RELEASE_VERSION", to: "\"\(releaseVersion)\""),
                .define("BUILDER_SHIM_VERSION", to: "\"\(builderShimVersion)\""),
            ]
        ),
    ]
)
