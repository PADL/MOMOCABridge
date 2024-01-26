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
import MOM
import Surrogate
import SwiftOCA
import SwiftOCADevice

class MOMExternalKey: SwiftOCADevice.OcaBooleanActuator, MOMKeyProtocol {
    // this is a subclass to clarify it does not implement GetSetting()
    override open class var classID: OcaClassID { OcaClassID(parent: super.classID, 65280) }

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

    override open func handleCommand(
        _ command: Ocp1Command,
        from controller: OcaController
    ) async throws -> Ocp1Response {
        do {
            return try await handleCommonMomCommand(command, from: controller)
        } catch let error as MOMStatus where error == .continue {
            switch command.methodID {
            case OcaMethodID("2.8"):
                guard let bridge else { throw Ocp1Error.status(.deviceError) }
                try await ensureReadable(by: controller)
                label = await bridge.userLabel(keyID: keyID, layer: bridge.selectedLayer)
                return try encodeResponse(label)
            case OcaMethodID("2.9"):
                guard let bridge else { throw Ocp1Error.status(.deviceError) }
                try await ensureWritable(by: controller)
                let label: OcaString = try decodeCommand(command)
                await bridge.setUserLabel(keyID: keyID, layer: bridge.selectedLayer, to: label)
            case OcaMethodID("5.1"):
                // being a footswitch with no visible state, this is never readable
                try await ensureReadable(by: controller)
                throw Ocp1Error.status(.notImplemented)
            case OcaMethodID("5.2"):
                try await ensureWritableAndConnectedToDadMan(controller)
                // this "set" command is momentary, it does not have any state
                await notifyKeyDownUp(from: controller)
            default:
                return try await super.handleCommand(command, from: controller)
            }
        }
        return Ocp1Response()
    }

    func getKeyState(event: MOMEvent, with params: inout [AnyObject]) async throws {
        if params.count < 1 {
            throw MOMStatus.invalidRequest
        }

        params.insert(NSNumber(value: 0), at: 1)
    }

    func reset() async {}
}
