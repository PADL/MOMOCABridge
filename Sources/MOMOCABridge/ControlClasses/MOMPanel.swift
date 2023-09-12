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

class MOMPanel: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaWorker> {
    var buttons = [MOMButton]()
    var external: MOMExternalKey
    var gain: MOMGainControl
    var layer: MOMLayerIndicator

    init(bridge: MOMOCABridge) async throws {
        for ledID in MOMLedID.allCases() {
            try await buttons.append(MOMButton(ledID: ledID, bridge: bridge))
        }
        external = try await MOMExternalKey(bridge: bridge)
        gain = try await MOMGainControl(bridge: bridge)
        layer = try await MOMLayerIndicator(bridge: bridge)

        try await super.init(role: "MOM", deviceDelegate: bridge.device, addToRootBlock: true)

        for button in buttons { try await add(actionObject: button) }
        try await add(actionObject: external)
        try await add(actionObject: gain)
        try await add(actionObject: layer)
    }

    func object(keyID: MOMKeyID) -> MOMKeyProtocol {
        keyID == .external ? external : buttons[keyID.rawValue]
    }

    func object(keyID: AnyObject) throws -> MOMKeyProtocol {
        guard let keyID = (keyID as? NSNumber)?.keyIDValue else {
            throw MOMStatus.invalidParameter
        }

        return object(keyID: keyID)
    }

    func object(ledID: MOMLedID) -> MOMButton {
        object(keyID: ledID.keyID) as! MOMButton
    }

    func object(ledID: AnyObject) throws -> MOMButton {
        guard let ledID = (ledID as? NSNumber)?.ledIDValue else {
            throw MOMStatus.invalidParameter
        }

        return object(ledID: ledID)
    }
}
