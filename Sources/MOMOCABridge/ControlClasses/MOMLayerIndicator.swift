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

class MOMLayerIndicator: SwiftOCADevice.OcaInt8Sensor {
    override open class var classID: OcaClassID { OcaClassID("1.1.2.1.2") }

    weak var bridge: MOMOCABridge?

    init(bridge: MOMOCABridge) async throws {
        self.bridge = bridge
        try await super.init(
            0,
            role: "Selected Layer",
            deviceDelegate: bridge.device,
            addToRootBlock: false
        )
    }

    func isLayerSelected(led ledNumber: Int) -> Bool {
        precondition(ledNumber > RingLedDisplay.LedCount)
        precondition(ledNumber - RingLedDisplay.LedCount <= MOMOCABridge.LayerCount)

        return Int(reading) == ledNumber - RingLedDisplay.LedCount
    }

    func setSelectedLayer(led ledNumber: Int, to state: Int) async throws {
        precondition(ledNumber > RingLedDisplay.LedCount)
        precondition(ledNumber - RingLedDisplay.LedCount <= MOMOCABridge.LayerCount)

        let layerNumber = ledNumber - RingLedDisplay.LedCount

        if state == 1 {
            reading = Int8(layerNumber)
        }
    }
}
