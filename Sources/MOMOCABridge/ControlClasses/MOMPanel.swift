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

protocol MOMPanelControl: SwiftOCADevice.OcaRoot {
  var bridge: MOMOCABridge? { get }

  func reset() async
}

extension MOMPanelControl {
  var isConnectedToDadMan: Bool {
    get async {
      await bridge?.isConnectedToDadMan ?? false
    }
  }

  func ensureWritableAndConnectedToDadMan(
    _ controller: OcaController,
    command: Ocp1Command
  ) async throws {
    guard let bridge else { return }
    try await ensureWritable(by: controller, command: command)
    try await bridge.ensureConnectedToDadMan()
  }

  // shared command implementations between MOM worker classes
  func handleCommonMomCommand(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("2.1"): // GetEnabled()
      try await ensureReadable(by: controller, command: command)
      return try encodeResponse(await isConnectedToDadMan)
    case OcaMethodID("2.2"): // SetEnabled()
      try await ensureWritable(by: controller, command: command)
      fallthrough
    default:
      throw MOMStatus.continue
    }
  }

  // we could implement this by simply changing the enabled property, but why make things simple?
  func portStatusDidChange() async throws {
    guard let bridge else { return }
    let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
    let parameters = await OcaPropertyChangedEventData<OcaBoolean>(
      propertyID: OcaPropertyID("2.1"), // enabled
      propertyValue: isConnectedToDadMan,
      changeType: .currentChanged
    )

    try await bridge.device.notifySubscribers(
      event,
      parameters: parameters
    )
  }
}

class MOMPanel: SwiftOCADevice.OcaBlock<SwiftOCADevice.OcaWorker>, MOMPanelControl {
  weak var bridge: MOMOCABridge?

  private var buttons = [MOMButton]()
  private var external: MOMExternalKey
  var gain: MOMSteppedGainControl
  var layer: MOMLayerIndicator
  var identificationSensor: MOMIdentificationSensor

  init(bridge: MOMOCABridge) async throws {
    self.bridge = bridge

    for ledID in MOMLedID.allCases() {
      try await buttons.append(MOMButton(ledID: ledID, bridge: bridge))
    }
    external = try await MOMExternalKey(bridge: bridge)
    gain = try await MOMSteppedGainControl(bridge: bridge)
    layer = try await MOMLayerIndicator(bridge: bridge)
    identificationSensor = try await MOMIdentificationSensor(bridge: bridge)

    try await super.init(role: "MOM", deviceDelegate: bridge.device, addToRootBlock: true)

    for button in buttons { try await add(actionObject: button) }
    try await add(actionObject: external)
    try await add(actionObject: gain)
    try await add(actionObject: layer)
    try await add(actionObject: identificationSensor)
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

  func object(keyID: MOMKeyID) -> MOMKeyProtocol {
    // NB: key IDs start at index 1
    keyID == .external ? external : buttons[keyID.rawValue - 1]
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

  // FIXME: ideally we could specialize on OcaWorker & MOMPanelControl
  private var panelMembers: [MOMPanelControl] {
    actionObjects.map { $0 as! MOMPanelControl }
  }

  func portStatusDidChange() async {
    for object in panelMembers {
      try? await object.portStatusDidChange()
    }
  }

  func reset() async {
    for object in panelMembers {
      await object.reset()
      try? await object.portStatusDidChange()
    }
  }
}
