//
// Copyright (c) 2018-2023 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an 'AS IS' BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

import Foundation
import Surrogate
import SwiftOCA
import SwiftOCADevice

class MOMExternalKey: SwiftOCADevice.OcaActuator, MOMKeyProtocol {
    override open class var classID: OcaClassID { OcaClassID("1.1.1.1.65280") }

    var keyID: MOMKeyID { .external }
    weak var bridge: MOMOCABridge?

    init(bridge: MOMOCABridge) async throws {
        self.bridge = bridge
        try await super.init(
            role: MOMKeyID.external.description,
            deviceDelegate: bridge.device,
            addToRootBlock: false
        )
    }

    func getKeyState(event: MOMEvent, with params: inout [AnyObject]) async throws {
        if params.count < 1 {
            throw MOMStatus.invalidRequest
        }

        params.insert(NSNumber(value: 0), at: 1)
    }

    override open func handleCommand(
        _ command: Ocp1Command,
        from controller: AES70OCP1Controller
    ) async throws -> Ocp1Response {
        switch command.methodID {
        case OcaMethodID("5.2"):
            // this "set" command is momentary, it does not have any state
            await notifyKeyDownUp(from: controller)
        default:
            return try await super.handleCommand(command, from: controller)
        }
        return Ocp1Response()
    }
}
