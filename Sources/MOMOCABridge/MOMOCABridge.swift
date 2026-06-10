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

import FlyingSocks
import Foundation
import MOM
import OSCOCABridge
import SwiftOCA
import SwiftOCADevice

// UserDefaults keys, preserved verbatim from the C Surrogate constants so
// existing user settings carry over.
private let kMOMDeviceIDDefaultsKey = "kMOMDeviceID"
private let kMOMDeviceNameDefaultsKey = "kMOMDeviceName"
private let kMOMLedIntensityDefaultsKey = "kMOMLedIntensity"

@OcaDevice
public class MOMOCABridge {
  static let defaultDeviceID: Int32 = 50

  private var momController: MOMController!
  private var momDiscoverabilityStatus: MOMStatus = .socketError
  private(set) var panel: MOMPanel!
  private var momDeviceNotificationTask: Task<(), Never>?
  private var ocp1Task: Task<(), Error>?
  private let oscBridge: OSCOCABridge?

  let device = OcaDevice.shared
  let endpoint: Ocp1DeviceEndpoint
  var ringLedDisplay = RingLedDisplay()

  deinit {
    momDeviceNotificationTask?.cancel()
  }

  public init(port: UInt16 = 65000, oscServerPort: UInt16? = nil) async throws {
    var localAddress = sockaddr_in()
    localAddress.sin_family = sa_family_t(AF_INET)
    localAddress.sin_addr.s_addr = INADDR_ANY
    localAddress.sin_port = port.bigEndian
    #if canImport(Darwin)
    localAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    #endif

    var localAddressData = Data()

    withUnsafeBytes(of: &localAddress) { bytes in
      localAddressData = Data(bytes: bytes.baseAddress!, count: bytes.count)
    }

    if let oscServerPort {
      localAddress.sin_port = oscServerPort.bigEndian
      oscBridge = OSCOCABridge(address: localAddress, device: OcaDevice.shared)
    } else {
      oscBridge = nil
    }

    try await device.initializeDefaultObjects()

    endpoint = try await Ocp1DeviceEndpoint(address: localAddressData, device: device)
    panel = try await MOMPanel(bridge: self)

    momController = momControllerCreate()
    await refreshDeviceManager()

    momDeviceNotificationTask = Task {
      guard let deviceManager = await self.device.deviceManager else { return }
      Task {
        for try await deviceName in deviceManager.$deviceName {
          let params: [MOMParameter] = [.int(Int32(MOMStatus.success.rawValue)),
                                    .string(deviceName),
                                    .string(deviceManager.userInventoryCode)]
          self.notify(event: .getDeviceID, params: params)
        }
      }
      Task {
        for try await deviceID in deviceManager.$userInventoryCode {
          let params: [MOMParameter] = [.int(Int32(MOMStatus.success.rawValue)),
                                    .string(deviceManager.deviceName),
                                    .string(deviceID)]
          self.notify(event: .getDeviceID, params: params)
        }
      }
    }

    if let oscBridge {
      log(message: "started OSC server on port \(oscServerPort!)")
      await oscBridge.run()
    }
  }

  private func momControllerCreate() -> MOMController {
    var options = MOMOptions()
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

    options.recoveryFirmwareTag = "version"
    options.recoveryFirmwareVersion = "SoftMOM \(appVersion ?? "0.0").\(appBuild ?? "0")"
    options.deviceID = deviceID ?? Self.defaultDeviceID
    options.deviceName = deviceName ?? "MOMOCABridge"
    // options.localInterfaceAddress = self.localInterfaceAddress
    if let serialNumber {
      options.serialNumber = serialNumber
    }

    log(message: "starting controller with \(options)")

    return MOMController(
      options: options,
      queue: DispatchQueue(label: "com.padl.MOMOCABridge.controller")
    ) { [weak self] controller, peer, event, params, sendReply in
      guard let self else { return .continue }
      Task<(), Never> {
        var params = params
        var status = MOMStatus.continue

        do {
          try await self.handle(event: event.event, with: &params)
          status = .success
        } catch let error as MOMStatus {
          status = error
        } catch {}
        if let sendReply {
          _ = sendReply(controller, peer, event, status, params)
        }
      }
      return .success
    }
  }

  public func endDiscoverability() throws {
    guard let momController else {
      throw MOMStatus.invalidParameter
    }

    if let ocp1Task {
      ocp1Task.cancel()
      self.ocp1Task = nil
    }

    log(message: "ending discoverability")
    _ = momController.endDiscoverability()
    momDiscoverabilityStatus = .socketError
  }

  public func beginDiscoverability() async throws {
    guard let momController,
          momDiscoverabilityStatus != .success
    else {
      throw MOMStatus.invalidParameter
    }

    momDiscoverabilityStatus = momController.beginDiscoverability()
    guard momDiscoverabilityStatus == .success else {
      log(message: "failed to begin discoverability")
      throw momDiscoverabilityStatus
    }

    log(message: "begun discoverability with options \(momController.options)")

    ocp1Task = Task { try await endpoint.run() }
  }

  public func announceDiscoverability() async throws {
    guard let momController else {
      throw MOMStatus.invalidParameter
    }

    let status = momController.announceDiscoverability()
    guard status == .success else {
      throw status
    }
  }

  func log(message: String) {
    NSLog("\(message)")
  }

  func notify(event: MOMEvent, params: [MOMParameter]) {
    _ = momController.notify(event, params: params)
  }

  var options: MOMOptions {
    momController.options
  }

  func reset() async {
    await refreshDeviceManager()
    await panel.reset()
    ringLedDisplay = RingLedDisplay()
  }
}

extension MOMOCABridge {
  private var userDefaults: UserDefaults {
    UserDefaults.standard
  }

  var deviceID: Int32? {
    get {
      (userDefaults.object(forKey: kMOMDeviceIDDefaultsKey) as? Int).map { Int32($0) }
    }
    set {
      userDefaults.set(newValue.map { Int($0) }, forKey: kMOMDeviceIDDefaultsKey)
    }
  }

  var deviceName: String? {
    get {
      userDefaults.object(forKey: kMOMDeviceNameDefaultsKey) as? String
    }
    set {
      userDefaults.set(newValue, forKey: kMOMDeviceNameDefaultsKey)
    }
  }

  var ledIntensity: MOMLedIntensity? {
    get {
      (userDefaults.object(forKey: kMOMLedIntensityDefaultsKey) as? Int)
        .flatMap(MOMLedIntensity.init(rawValue:))
    }

    set {
      userDefaults.set(newValue?.rawValue, forKey: kMOMLedIntensityDefaultsKey)
    }
  }

  private func userLabelDefaultsKey(keyID: MOMKeyID, layer: Int) -> String {
    "kMOMUserLabel.Layer" + String(describing: layer) + "." + keyID.labelSuffix
  }

  private func defaultLabel(keyID: MOMKeyID) -> String {
    let defaultsKey = userLabelDefaultsKey(keyID: keyID, layer: 1)
    return keyID.rawValue <= MOMKeyID.sourceC.rawValue ? String(defaultsKey.last!) : ""
  }

  func setUserLabel(keyID: MOMKeyID, layer: Int, to label: String) async {
    // if the label is reset to the empty string or the default value, remove it
    let label = label.isEmpty || label == defaultLabel(keyID: keyID) ? nil : label
    let userDefaults = UserDefaults.standard
    let defaultsKey = userLabelDefaultsKey(keyID: keyID, layer: layer)

    userDefaults.set(label, forKey: defaultsKey)
    let object = panel.object(keyID: keyID)
    try? await object.labelDidChange()
  }

  func userLabel(keyID: MOMKeyID, layer: Int) -> String {
    let userDefaults = UserDefaults.standard
    let defaultsKey = userLabelDefaultsKey(keyID: keyID, layer: layer)

    guard let userLabel = userDefaults.object(forKey: defaultsKey) as? String,
          userLabel.isEmpty == false
    else {
      return defaultLabel(keyID: keyID)
    }

    return userLabel
  }
}

extension MOMOCABridge {
  func refreshDeviceManager() async {
    guard let deviceManager = await device.deviceManager else { return }

    let options = options
    deviceManager.serialNumber = options.serialNumber
    deviceManager.deviceName = options.deviceName
    deviceManager.userInventoryCode = String(options.deviceID)
    deviceManager.deviceRevisionID = options.systemTypeAndVersion
  }

  var serialNumber: String? {
    guard let serialNumberUUID = UUID.platformUUID else {
      return nil
    }

    return Self.serialNumber(from: serialNumberUUID)
  }

  private static func serialNumber(from serialNumberUUID: UUID) -> String {
    let base64String = serialNumberUUID.base64String
    let index = base64String.index(base64String.startIndex, offsetBy: 14)

    return "710" + base64String[index...]
  }

  func withDeviceManager(
    event status: MOMEvent,
    with params: inout [MOMParameter],
    _ block: @escaping (SwiftOCADevice.OcaDeviceManager, inout [MOMParameter]) async throws -> ()
  ) async throws {
    guard let deviceManager = await device.deviceManager else {
      throw MOMStatus.continue
    }
    var params = params
    try await block(deviceManager, &params)
  }

  func setDeviceID(event status: MOMEvent, with params: inout [MOMParameter]) async throws {
    try await withDeviceManager(event: status, with: &params) { _, params in
      if case let .int(deviceID) = params.first {
        self.deviceID = deviceID
        await self.refreshDeviceManager()
      }

      if params.count > 1, case let .string(deviceName) = params[1] {
        self.deviceName = deviceName
        await self.refreshDeviceManager()
      }
    }
  }
}

private extension OcaDeviceState {
  var isOperational: Bool {
    self == .operational
  }
}

extension MOMOCABridge {
  private func portStatusChanged(
    event portStatus: MOMEvent,
    with params: inout [MOMParameter]
  ) async throws {
    try await withDeviceManager(event: portStatus, with: &params) { deviceManager, _ in
      let oldState = deviceManager.state

      switch portStatus {
      case .portError:
        deviceManager.state = .error
      case .portOpen:
        deviceManager.state = .initializing
      case .portReady:
        deviceManager.state = .updating
      case .portConnected:
        deviceManager.state = .operational
      case .portClosed:
        deviceManager.state = .disabled
        await self.reset()
        return // this implicitly calls portStatusDidChange()
      default:
        break
      }

      if oldState.isOperational != deviceManager.state.isOperational {
        // notify subscribers to Enabled property of change in status
        await self.panel.portStatusDidChange()
      }
    }
  }

  var isConnectedToDadMan: Bool {
    get async {
      guard let deviceManager = await device.deviceManager else {
        return false
      }
      return deviceManager.state == .operational
    }
  }

  func ensureConnectedToDadMan() async throws {
    guard await isConnectedToDadMan else {
      throw Ocp1Error.status(.deviceError)
    }
  }

  func handle(event: MOMEvent, with params: inout [MOMParameter]) async throws {
    switch event {
    case .portError:
      fallthrough
    case .portClosed:
      fallthrough
    case .portReady:
      fallthrough
    case .portOpen:
      fallthrough
    case .portConnected:
      try await portStatusChanged(event: event, with: &params)
    case .identify:
      try await panel.identificationSensor.identify()
    case .setDeviceID:
      try await setDeviceID(event: event, with: &params)
    case .getKeyState:
      try await panel.object(keyID: params.first).getKeyState(event: event, with: &params)
    case .getLedState:
      try await panel.object(ledID: params.first).getLedState(event: event, with: &params)
    case .setLedState:
      try await panel.object(ledID: params.first).setLedState(event: event, with: &params)
    case .getLedIntensity:
      try await getLedIntensity(event: event, with: &params)
    case .setLedIntensity:
      try await setLedIntensity(event: event, with: &params)
    case .getRingLedState:
      try await getRingLedState(event: event, with: &params)
    case .setRingLedState:
      try await setRingLedState(event: event, with: &params)
    case .getRotationCount:
      try await panel.gain.getRotationCount(event: event, with: &params)
    default:
      throw MOMStatus.continue
    }
  }
}

extension MOMOCABridge {
  static let LayerCount = 4

  func getRingLedState(event: MOMEvent, with params: inout [MOMParameter]) async throws {
    if params.count < 1 {
      throw MOMStatus.invalidRequest
    }

    guard case let .int(ledNumber) = params[0] else {
      throw MOMStatus.invalidParameter
    }

    if ledNumber < 1 ||
      Int(ledNumber) > RingLedDisplay.LedCount + Self.LayerCount
    {
      throw MOMStatus.invalidParameter
    }

    if Int(ledNumber) <= RingLedDisplay.LedCount {
      params.insert(.int(Int32(panel.gain.getVolume(led: Int(ledNumber)))), at: 1)
    } else {
      params.insert(
        .bool(panel.layer.isLayerSelected(led: Int(ledNumber))),
        at: 1
      )
    }
  }

  func setRingLedState(event: MOMEvent, with params: inout [MOMParameter]) async throws {
    if params.count < 2 {
      throw MOMStatus.invalidRequest
    }

    guard case let .int(ledNumber) = params[0] else {
      throw MOMStatus.invalidParameter
    }

    if ledNumber < 1 ||
      Int(ledNumber) > RingLedDisplay.LedCount + Self.LayerCount
    {
      throw MOMStatus.invalidParameter
    }

    guard case let .int(ledParam) = params[1] else {
      throw MOMStatus.invalidParameter
    }

    if Int(ledNumber) <= RingLedDisplay.LedCount {
      try await panel.gain.setVolume(led: Int(ledNumber), toIntensity: Int(ledParam))
    } else {
      try await panel.layer.setSelectedLayer(led: Int(ledNumber), to: Int(ledParam))
    }
  }

  func updateRingLedDisplay(led ledNumber: Int, to color: RingLedDisplay.LedColor) {
    ringLedDisplay.update(led: ledNumber, to: color)
  }

  var selectedLayer: Int {
    Int(panel.layer.reading.value)
  }
}

extension MOMOCABridge {
  func getLedIntensity(event: MOMEvent, with params: inout [MOMParameter]) async throws {
    let intensity = ledIntensity ?? .normal
    params.insert(.int(Int32(intensity.rawValue)), at: 0)
  }

  func setLedIntensity(event: MOMEvent, with params: inout [MOMParameter]) async throws {
    if params.count < 1 {
      throw MOMStatus.invalidRequest
    }

    guard case let .int(ledIntensityParam) = params[0] else {
      throw MOMStatus.invalidParameter
    }

    guard let ledIntensity = MOMLedIntensity(rawValue: Int(ledIntensityParam)) else {
      throw MOMStatus.invalidParameter
    }

    self.ledIntensity = ledIntensity
  }
}
