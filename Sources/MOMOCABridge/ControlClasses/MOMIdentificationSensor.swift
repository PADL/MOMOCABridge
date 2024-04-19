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

class MOMIdentificationSensor: SwiftOCADevice.OcaIdentificationSensor, MOMPanelControl {
    weak var bridge: MOMOCABridge?

    init(bridge: MOMOCABridge) async throws {
        self.bridge = bridge
        try await super.init(
            role: "Identify",
            deviceDelegate: bridge.device,
            addToRootBlock: false
        )
        state = .valid
    }

    required init(from decoder: Decoder) throws {
        throw Ocp1Error.notImplemented
    }

    override open func handleCommand(
        _ command: Ocp1Command,
        from controller: OcaController
    ) async throws -> Ocp1Response {
        do {
            return try await handleCommonMomCommand(command, from: controller)
        } catch let error as MOMStatus where error == .continue {
            return try await super.handleCommand(command, from: controller)
        }
    }

    func reset() async {}
}
