//
// Copyright (c) 2025 PADL Software Pty Ltd
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

#if canImport(OSCKit)

import OSCKitCore
import SwiftOCA
import SwiftOCADevice
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

fileprivate extension OcaDevice {
  // walk root block
  func _resolve(namePath: OcaNamePath) async throws -> OcaONo? {
    try await rootBlock.find(actionObjectsByRolePath: namePath, resultFlags: .oNo).first?.oNo
  }

  func _bridgeOscMessage(_ message: OSCMessage) async throws -> Ocp1Command {
    let (ocaNamePath, ocaMethodID) = try message.addressPattern._bridgeToOcaPathAndMethodID()
    guard let oNo = try await _resolve(namePath: ocaNamePath) else {
      throw Ocp1Error.status(.processingFailed)
    }

    let encodedValues = try message.values.map { value in
      guard let value = value as? Encodable else { throw Ocp1Error.status(.invalidRequest) }
      let encoded: Data = try Ocp1Encoder().encode(value)
      return encoded
    }

    let parameters = Ocp1Parameters(
      parameterCount: OcaUint8(message.values.count),
      parameterData: encodedValues._flattened
    )

    return Ocp1Command(handle: 0, targetONo: oNo, methodID: ocaMethodID, parameters: parameters)
  }
}

public actor OCAOSCBridge: OcaController {
  let device: OcaDevice

  public init(device: OcaDevice) {
    self.device = device
  }

  public func handle(
    message: OSCMessage,
    timeTag: OSCTimeTag,
    host: String,
    port: UInt16
  ) async throws {
    let command = try await device._bridgeOscMessage(message)
    let result = await device.handleCommand(command, from: self)
    debugPrint("mapped \(message) -> \(command), result: \(result)")
  }
}

public extension OCAOSCBridge {
  func addSubscription(
    _ subscription: SwiftOCADevice
      .OcaSubscriptionManagerSubscription
  ) async throws {}

  func removeSubscription(
    _ subscription: SwiftOCADevice
      .OcaSubscriptionManagerSubscription
  ) async throws {}

  func removeSubscription(
    _ event: SwiftOCA.OcaEvent,
    property: SwiftOCA.OcaPropertyID?,
    subscriber: SwiftOCA.OcaMethod
  ) async throws {}

  func sendMessage(
    _ message: any SwiftOCA.Ocp1Message,
    type messageType: SwiftOCA.OcaMessageType
  ) async throws {}
}

fileprivate extension OSCAddressPattern {
  func _bridgeToOcaPathAndMethodID() throws -> (OcaNamePath, OcaMethodID) {
    guard pathComponents.count > 1 else {
      throw Ocp1Error.status(.badMethod)
    }

    let ocaNamePath = pathComponents[0..<(pathComponents.count - 1)].map { String($0) }
    let ocaMethodID = try OcaMethodID(unsafeString: String(pathComponents.last!))

    return (ocaNamePath, ocaMethodID)
  }
}

fileprivate extension [Data] {
  var _flattened: Data {
    reduce(Data()) {
      var data = $0
      data.append($1)
      return data
    }
  }
}

#endif
