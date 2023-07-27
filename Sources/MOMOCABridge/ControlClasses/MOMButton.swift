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

protocol MOMKeyProtocol: MOMPanelControl {
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

    // this needs to be called every time we update the layer text or change layer
    func notifyLabelChanged() async throws {
        guard let bridge else { return }
        let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
        let encoder = Ocp1BinaryEncoder()
        let parameters = await OcaPropertyChangedEventData<OcaString>(
            propertyID: OcaPropertyID("2.3"), // label
            propertyValue: bridge.userLabel(keyID: keyID, layer: bridge.selectedLayer),
            changeType: .currentChanged
        )

        try await bridge.device.notifySubscribers(
            event,
            parameters: try encoder.encode(parameters)
        )
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
        do {
            return try await handleCommonMomCommand(command, from: controller)
        } catch Ocp1Error.unhandledMethod {
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
            case OcaMethodID("5.2"):
                try await ensureWritableAndConnectedToDadMan(controller)
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

    func reset() async {
        setting = false
    }
}
