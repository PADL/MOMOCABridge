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

protocol MOMKeyProtocol {
    var keyID: MOMKeyID { get }
    var bridge: MOMOCABridge? { get }

    func getKeyState(event: MOMEvent, with params: inout [AnyObject]) async throws
}

extension MOMKeyProtocol {
    func notifyKeyDownUp(from controller: AES70OCP1Controller) async {
        guard let bridge else { return }
        var params: [Int] = [MOMStatus.success.rawValue, keyID.rawValue, 0]
        params[2] = 1 // key down
        await bridge.notifyDeferred(event: MOMEvent.getKeyState, params: params.nsNumberArray)
        params[2] = 0 // key up
        await bridge.notifyDeferred(event: MOMEvent.getKeyState, params: params.nsNumberArray)
        await bridge.sendDeferred()
    }
}

class MOMButton: SwiftOCADevice.OcaBooleanActuator, MOMKeyProtocol {
    let keyID: MOMKeyID
    weak var bridge: MOMOCABridge?

    init(keyID: MOMKeyID, bridge: MOMOCABridge) async throws {
        self.keyID = keyID
        self.bridge = bridge
        try await super.init(
            role: keyID.description,
            deviceDelegate: bridge.device,
            addToRootBlock: false
        )
    }

    convenience init(ledID: MOMLedID, bridge: MOMOCABridge) async throws {
        try await self.init(keyID: ledID.keyID, bridge: bridge)
    }

    override open func handleCommand(
        _ command: Ocp1Command,
        from controller: AES70OCP1Controller
    ) async throws -> Ocp1Response {
        switch command.methodID {
        case OcaMethodID("5.2"):
            // If the OCA controller changed what we think the state is, then toggle it.
            // We rely on DADman notifications to send OCA events, so we don't actually
            // change our representation of the state (in setting) here. Otherwise we
            // would end up broadcasting OCA events twice.
            let newState: OcaBoolean = try decodeCommand(command)
            guard newState != setting else { break }
            await notifyKeyDownUp(from: controller)
        default:
            return try await super.handleCommand(command, from: controller)
        }
        return Ocp1Response()
    }

    func getKeyState(event: MOMEvent, with params: inout [AnyObject]) async throws {
        if params.count < 1 {
            throw MOMStatus.invalidRequest
        }

        params.insert(NSNumber(value: setting), at: 1)
    }

    func setLedState(event: MOMEvent, with params: inout [AnyObject]) async throws {
        if params.count < 2 {
            throw MOMStatus.invalidRequest
        }

        guard let ledState = (params[1] as? NSNumber)?.boolValue else {
            throw MOMStatus.invalidParameter
        }

        setting = ledState
        if keyID == .ref {
            await bridge?.panel.gain.isGainAdjustable = !ledState
        }
    }

    func getLedState(event: MOMEvent, with params: inout [AnyObject]) async throws {
        if params.count < 1 {
            throw MOMStatus.invalidRequest
        }

        params.insert(NSNumber(value: setting), at: 1)
    }
}
