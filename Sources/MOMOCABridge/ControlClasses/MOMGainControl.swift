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

class MOMGainControl: SwiftOCADevice.OcaGain {
    weak var bridge: MOMOCABridge?
    var isGainAdjustable = true
    var rotaryEncoder = RotaryEncoder()

    init(bridge: MOMOCABridge) async throws {
        self.bridge = bridge
        try await super.init(
            role: "Gain",
            deviceDelegate: bridge.device,
            addToRootBlock: false
        )
        gain = OcaBoundedPropertyValue<OcaDB>(
            value: 0.0,
            in: MOM.dBDadDisplayFloor...MOM.dBDadDisplayCeiling
        )
    }

    override open func handleCommand(
        _ command: Ocp1Command,
        from controller: AES70Controller
    ) async throws -> Ocp1Response {
        switch command.methodID {
        case OcaMethodID("4.2"):
            if !isGainAdjustable {
                throw Ocp1Error.status(.parameterOutOfRange)
            }
            let newValue: OcaDB = try decodeCommand(command)
            await rotateEncoder(to: newValue, from: gain.value)
        default:
            return try await super.handleCommand(command, from: controller)
        }
        return Ocp1Response()
    }

    func getRotationCount(
        event: MOMEvent,
        with params: inout [AnyObject]
    ) async throws {
        params.insert(NSNumber(value: rotaryEncoder.rotationCount), at: 0)
    }

    func notifyRotationCount() async {
        let params: [Int] = [MOMStatus.success.rawValue, Int(rotaryEncoder.rotationCount)]
        await bridge?.notify(event: MOMEvent.getRotationCount, params: params.nsNumberArray)
    }

    func rotateEncoder(to newValueDB: OcaDB, from oldValueDB: OcaDB) async {
        let previousRotationCount = rotaryEncoder.rotationCount

        rotaryEncoder.rotateScaledDB(to: newValueDB, from: oldValueDB)

        if rotaryEncoder.rotationCount != previousRotationCount {
            await notifyRotationCount()
        }
    }

    func getVolume(led ledNumber: Int) -> Int {
        let color = RingLedDisplay.colorForDBValue(
            led: ledNumber,
            value: gain.value
        )

        return color.rawValue
    }

    func setVolume(led ledNumber: Int, toIntensity ledIntensity: Int) async throws {
        guard let color = RingLedDisplay.LedColor(rawValue: ledIntensity) else {
            throw MOMStatus.invalidParameter
        }

        guard let bridge else { return }
        await bridge.updateRingLedDisplay(led: ledNumber, to: color)

        if let dBValue = await bridge.ringLedDisplay.dBValue {
            gain.value = dBValue
        }
    }
}
