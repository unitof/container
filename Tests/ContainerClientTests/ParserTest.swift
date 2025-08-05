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

//

import ContainerizationError
import Foundation
import Testing

@testable import ContainerClient

struct ParserTest {
    @Test
    func testPublishPortParserTcp() throws {
        let result = try Parser.publishPorts(["127.0.0.1:8080:8000/tcp"])
        #expect(result.count == 1)
        #expect(result[0].hostAddress == "127.0.0.1")
        #expect(result[0].hostPort == UInt16(8080))
        #expect(result[0].containerPort == UInt16(8000))
        #expect(result[0].proto == .tcp)
    }

    @Test
    func testPublishPortParserUdp() throws {
        let result = try Parser.publishPorts(["192.168.32.36:8000:8080/UDP"])
        #expect(result.count == 1)
        #expect(result[0].hostAddress == "192.168.32.36")
        #expect(result[0].hostPort == UInt16(8000))
        #expect(result[0].containerPort == UInt16(8080))
        #expect(result[0].proto == .udp)
    }

    @Test
    func testPublishPortNoHostAddress() throws {
        let result = try Parser.publishPorts(["8080:8000/tcp"])
        #expect(result.count == 1)
        #expect(result[0].hostAddress == "0.0.0.0")
        #expect(result[0].hostPort == UInt16(8080))
        #expect(result[0].containerPort == UInt16(8000))
        #expect(result[0].proto == .tcp)
    }

    @Test
    func testPublishPortNoProtocol() throws {
        let result = try Parser.publishPorts(["8080:8000"])
        #expect(result.count == 1)
        #expect(result[0].hostAddress == "0.0.0.0")
        #expect(result[0].hostPort == UInt16(8080))
        #expect(result[0].containerPort == UInt16(8000))
        #expect(result[0].proto == .tcp)
    }

    @Test
    func testPublishPortInvalidProtocol() throws {
        #expect {
            _ = try Parser.publishPorts(["8080:8000/sctp"])
        } throws: { error in
            guard let error = error as? ContainerizationError else {
                return false
            }
            return error.description.contains("invalid publish protocol")
        }
    }

    @Test
    func testPublishPortInvalidValue() throws {
        #expect {
            _ = try Parser.publishPorts([""])
        } throws: { error in
            guard let error = error as? ContainerizationError else {
                return false
            }
            return error.description.contains("invalid publish value")
        }
    }

    @Test
    func testPublishPortInvalidAddress() throws {
        #expect {
            _ = try Parser.publishPorts(["1234"])
        } throws: { error in
            guard let error = error as? ContainerizationError else {
                return false
            }
            return error.description.contains("invalid publish address")
        }
    }

    @Test
    func testPublishPortInvalidHostPort() throws {
        #expect {
            _ = try Parser.publishPorts(["foo:1234"])
        } throws: { error in
            guard let error = error as? ContainerizationError else {
                return false
            }
            return error.description.contains("invalid publish host port")
        }
    }

    @Test
    func testPublishPortInvalidContainerPort() throws {
        #expect {
            _ = try Parser.publishPorts(["1234:foo"])
        } throws: { error in
            guard let error = error as? ContainerizationError else {
                return false
            }
            return error.description.contains("invalid publish container port")
        }
    }
}
