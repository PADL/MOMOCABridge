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

import CoreFoundation
import FlyingSocks
import Foundation
import MOM
import Surrogate
import SwiftOCA
import SwiftOCADevice

extension MOMStatus: Error {}

public actor MOMOCABridge {
    static var defaultDeviceID = 50

    private var momController: MOMControllerRef!
    private var momDiscoverabilityStatus: MOMStatus = .socketError
    private(set) var panel: MOMPanel!
    private var momDeviceNotificationTask: Task<(), Never>?

    let device = AES70Device.shared
    let listener: AES70OCP1Listener
    var ringLedDisplay = RingLedDisplay()

    deinit {
        momDeviceNotificationTask?.cancel()
        MOMControllerRelease(momController)
    }

    public init(port: UInt16 = 65000) async throws {
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

        listener = try await AES70OCP1Listener(device: device, address: localAddressData)
        panel = try await MOMPanel(bridge: self)

        momController = momControllerCreate()
        await refreshDeviceManager()

        momDeviceNotificationTask = Task {
            guard let deviceManager = await self.device.deviceManager else { return }
            Task {
                for try await deviceName in deviceManager.$deviceName {
                    let params: [AnyObject] = [NSNumber(value: MOMStatus.success.rawValue),
                                               deviceName as NSString,
                                               deviceManager.userInventoryCode as NSString]
                    self.notify(event: .getDeviceID, params: params)
                }
            }
            Task {
                for try await deviceID in deviceManager.$userInventoryCode {
                    let params: [AnyObject] = [NSNumber(value: MOMStatus.success.rawValue),
                                               deviceManager.deviceName as NSString,
                                               deviceID as NSString]
                    self.notify(event: .getDeviceID, params: params)
                }
            }
        }
    }

    private func momControllerCreate() -> MOMControllerRef? {
        let options = NSMutableDictionary()
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

        options[kMOMRecoveryFirmwareTag] = "version"
        options[kMOMRecoveryFirmwareVersion] = "SoftMOM \(appVersion ?? "0.0").\(appBuild ?? "0")"
        options[kMOMDeviceID] = deviceID ?? Self.defaultDeviceID
        options[kMOMDeviceName] = deviceName ?? "MOMOCABridge"
        // options[kMOMLocalInterfaceAddress]      = self.localInterfaceAddress
        options[kMOMSerialNumber] = serialNumber

        log(message: "starting controller with \(options)")

        let momController = MOMControllerCreate(
            kCFAllocatorDefault,
            options,
            RunLoop.main
                .getCFRunLoop()
        ) { [weak self] (
            controller: MOMControllerRef,
            context: OpaquePointer,
            event: MOMEvent,
            params: CFArray,
            sendReply: MOMSendReplyCallback?
        ) -> MOMStatus in
            guard let self else { return .continue }
            Task<(), Never> {
                var params = params as [AnyObject]
                var status = MOMStatus.continue

                do {
                    try await self.handle(event: MOMEventGetEvent(event), with: &params)
                    status = .success
                } catch let error as MOMStatus {
                    status = error
                } catch {}
                if let sendReply {
                    _ = sendReply(controller, context, event, status, params as NSArray)
                }
            }
            return .success
        }

        return momController
    }

    public func endDiscoverability() throws {
        guard let momController = momController else {
            throw MOMStatus.invalidParameter
        }

        log(message: "ending discoverability")
        MOMControllerEndDiscoverability(momController)
        momDiscoverabilityStatus = .socketError
    }

    public func beginDiscoverability() async throws {
        guard let momController = momController,
              momDiscoverabilityStatus != .success
        else {
            throw MOMStatus.invalidParameter
        }

        momDiscoverabilityStatus = MOMControllerBeginDiscoverability(momController)
        guard momDiscoverabilityStatus == .success else {
            log(message: "failed to begin discoverability")
            throw momDiscoverabilityStatus
        }

        let options = MOMControllerGetOptions(momController) as NSMutableDictionary
        log(message: "begun discoverability with options \(options)")

        try await listener.start()
    }

    public func announceDiscoverability() async throws {
        await listener.stop()

        guard let momController = momController else {
            throw MOMStatus.invalidParameter
        }

        let status = MOMControllerAnnounceDiscoverability(momController)
        guard status == .success else {
            throw status
        }
    }

    func log(message: String) {
        NSLog("\(message)")
    }

    func notify(event: MOMEvent, params: [AnyObject]) {
        MOMControllerNotify(momController, event, params as NSArray)
    }

    func notifyDeferred(event: MOMEvent, params: [AnyObject]) {
        MOMControllerNotifyDeferred(momController, event, params as NSArray)
    }

    func sendDeferred() {
        MOMControllerSendDeferred(momController)
    }

    var options: [NSString: AnyObject] {
        MOMControllerGetOptions(momController) as! [NSString: AnyObject]
    }

    func reset() async {
        await refreshDeviceManager()
        await panel.reset()
        ringLedDisplay = RingLedDisplay()
    }
}

private let kMOMLedIntensity = "kMOMLedIntensity"

extension MOMOCABridge {
    private var userDefaults: UserDefaults {
        UserDefaults.standard
    }

    var deviceID: Int? {
        get {
            userDefaults.object(forKey: kMOMDeviceID as String) as? Int
        }
        set {
            userDefaults.set(newValue, forKey: kMOMDeviceID as String)
        }
    }

    var deviceName: String? {
        get {
            userDefaults.object(forKey: kMOMDeviceName as String) as? String
        }
        set {
            userDefaults.set(newValue, forKey: kMOMDeviceName as String)
        }
    }

    var ledIntensity: MOMLedIntensity? {
        get {
            userDefaults.object(forKey: kMOMLedIntensity) as? MOMLedIntensity
        }

        set {
            userDefaults.set(newValue, forKey: kMOMLedIntensity as String)
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

        deviceManager.serialNumber = options[kMOMSerialNumber] as! String
        deviceManager.deviceName = options[kMOMDeviceName] as! String
        deviceManager
            .userInventoryCode = String(options[kMOMDeviceID] as? Int ?? Self.defaultDeviceID)
        deviceManager.deviceRevisionID = options[kMOMSystemTypeAndVersion] as! String
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
        with params: inout [AnyObject],
        _ block: @escaping (SwiftOCADevice.OcaDeviceManager, inout [AnyObject]) async throws -> ()
    ) async throws {
        guard let deviceManager = await device.deviceManager else {
            throw MOMStatus.continue
        }
        var params = params
        try await block(deviceManager, &params)
    }

    func setDeviceID(event status: MOMEvent, with params: inout [AnyObject]) async throws {
        try await withDeviceManager(event: status, with: &params) { _, params in
            if let deviceID = params[0] as? Int {
                self.deviceID = deviceID
                await self.refreshDeviceManager()
            }

            if let deviceName = params[1] as? String {
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
        with params: inout [AnyObject]
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

    func handle(event: MOMEvent, with params: inout [AnyObject]) async throws {
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
            try await panel.object(keyID: params[0]).getKeyState(event: event, with: &params)
        case .getLedState:
            try await panel.object(ledID: params[0]).getLedState(event: event, with: &params)
        case .setLedState:
            try await panel.object(ledID: params[0]).setLedState(event: event, with: &params)
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

    func getRingLedState(event: MOMEvent, with params: inout [AnyObject]) async throws {
        if params.count < 1 {
            throw MOMStatus.invalidRequest
        }

        guard let ledNumber = (params[0] as? NSNumber)?.intValue else {
            throw MOMStatus.invalidParameter
        }

        if ledNumber < 1 || ledNumber > RingLedDisplay.LedCount + Self.LayerCount {
            throw MOMStatus.invalidParameter
        }

        if ledNumber <= RingLedDisplay.LedCount {
            params.insert(NSNumber(value: panel.gain.getVolume(led: ledNumber)), at: 1)
        } else {
            params.insert(NSNumber(value: panel.layer.isLayerSelected(led: ledNumber)), at: 1)
        }
    }

    func setRingLedState(event: MOMEvent, with params: inout [AnyObject]) async throws {
        if params.count < 2 {
            throw MOMStatus.invalidRequest
        }

        guard let ledNumber = (params[0] as? NSNumber)?.intValue else {
            throw MOMStatus.invalidParameter
        }

        if ledNumber < 1 || ledNumber > RingLedDisplay.LedCount + Self.LayerCount {
            throw MOMStatus.invalidParameter
        }

        guard let ledParam = (params[1] as? NSNumber)?.intValue else {
            throw MOMStatus.invalidParameter
        }

        if ledNumber <= RingLedDisplay.LedCount {
            try await panel.gain.setVolume(led: ledNumber, toIntensity: ledParam)
        } else {
            try await panel.layer.setSelectedLayer(led: ledNumber, to: ledParam)
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
    func getLedIntensity(event: MOMEvent, with params: inout [AnyObject]) async throws {
        if let ledIntensity = ledIntensity {
            params.insert(NSNumber(value: ledIntensity.rawValue), at: 0)
        } else {
            params.insert(NSNumber(value: MOMLedIntensity.normal.rawValue), at: 0)
        }
    }

    func setLedIntensity(event: MOMEvent, with params: inout [AnyObject]) async throws {
        if params.count < 1 {
            throw MOMStatus.invalidRequest
        }

        guard let ledIntensityParam = (params[0] as? NSNumber)?.intValue else {
            throw MOMStatus.invalidParameter
        }

        guard let ledIntensity = MOMLedIntensity(rawValue: ledIntensityParam) else {
            throw MOMStatus.invalidParameter
        }

        self.ledIntensity = ledIntensity
    }
}
