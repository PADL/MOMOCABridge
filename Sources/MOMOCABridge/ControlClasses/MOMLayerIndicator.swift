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

class MOMLayerIndicator: SwiftOCADevice.OcaUint8Sensor, MOMPanelControl {
    override open class var classID: OcaClassID { OcaClassID(parent: super.classID, 65280) }

    weak var bridge: MOMOCABridge?

    init(bridge: MOMOCABridge) async throws {
        self.bridge = bridge
        try await super.init(
            OcaBoundedPropertyValue<OcaUint8>(value: 1, in: 1...4),
            role: "Selected Layer",
            deviceDelegate: bridge.device,
            addToRootBlock: false
        )
        state = .valid
    }

    override open func handleCommand(
        _ command: Ocp1Command,
        from controller: AES70Controller
    ) async throws -> Ocp1Response {
        do {
            return try await handleCommonMomCommand(command, from: controller)
        } catch let error as MOMStatus where error == .continue {
            return try await super.handleCommand(command, from: controller)
        }
    }

    func isLayerSelected(led ledNumber: Int) -> Bool {
        precondition(ledNumber > RingLedDisplay.LedCount)
        precondition(ledNumber - RingLedDisplay.LedCount <= MOMOCABridge.LayerCount)

        return Int(reading.value) == ledNumber - RingLedDisplay.LedCount
    }

    func setSelectedLayer(led ledNumber: Int, to state: Int) async throws {
        precondition(ledNumber > RingLedDisplay.LedCount)
        precondition(ledNumber - RingLedDisplay.LedCount <= MOMOCABridge.LayerCount)

        let layerNumber = ledNumber - RingLedDisplay.LedCount

        if state == 1 {
            reading.value = OcaUint8(layerNumber)
            await layerDidChange()
        }
    }

    func layerDidChange() async {
        guard let bridge else { return }
        for keyID in MOMKeyID.allCases() {
            let object = await bridge.panel.object(keyID: keyID)
            try? await object.labelDidChange()
        }
    }

    func reset() async {
        await layerDidChange()
    }
}
