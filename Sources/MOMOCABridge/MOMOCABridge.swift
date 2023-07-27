import CoreFoundation
import Foundation
import Surrogate
import SwiftOCA
import SwiftOCADevice

@main
public actor MOMOCABridge {
    static func main() {
        
    }

    static internal var defaultDeviceID = 50

    internal var momController: MOMControllerRef?
    internal var momDiscoverabilityStatus: MOMStatus = .socketError
    internal var ringLedDisplay = RingLedDisplay()
    internal var rotaryEncoder = RotaryEncoder()
    internal var portStatus: MOMEvent = .portClosed

    deinit {
        if let momController = self.momController {
            MOMControllerRelease(momController)
            self.momController = nil
        }
    }
        
    private func momControllerCreate() -> MOMControllerRef? {
        let options = NSMutableDictionary()
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        
        options[kMOMRecoveryFirmwareTag]        = "version"
        options[kMOMRecoveryFirmwareVersion]    = "SoftMOM \(appVersion ?? "0.0").\(appBuild ?? "0")"
        options[kMOMDeviceID]                   = Self.defaultDeviceID    // don't conflict with MOM, iOS app defaults
        options[kMOMDeviceName]                 = "StreamDeck"
        //options[kMOMLocalInterfaceAddress]      = self.localInterfaceAddress
        //options[kMOMSerialNumber]               = self.serialNumber

        self.log(message: "starting controller with \(options)")
        
        let momController = MOMControllerCreate(kCFAllocatorDefault,
                                                options,
                                                RunLoop.current.getCFRunLoop(),
                                                {[weak self] (controller: MOMControllerRef, event: MOMEvent, params: NSMutableArray) -> MOMStatus in
            return .invalidRequest
        })
        
        return momController
    }
    
    @discardableResult internal func endDiscoverability() -> MOMStatus {
        guard let momController = self.momController else {
            return .invalidParameter
        }

        self.log(message: "ending discoverability")
        MOMControllerEndDiscoverability(momController)
        self.momDiscoverabilityStatus = .socketError
        
        return .success
    }
    
    @discardableResult internal func beginDiscoverability() -> MOMStatus {
        guard let momController = self.momController,
              self.momDiscoverabilityStatus != .success else {
            return .invalidParameter
        }
       
        self.momDiscoverabilityStatus = MOMControllerBeginDiscoverability(momController)
        guard self.momDiscoverabilityStatus == .success else {
            self.log(message: "failed to begin discoverability")
            return self.momDiscoverabilityStatus
        }

        let options = MOMControllerGetOptions(momController) as NSMutableDictionary
        self.log(message: "begun discoverability with options \(options)")
        
        return .success
    }
    
    @discardableResult internal func announceDiscoverability() -> MOMStatus {
        guard let momController = self.momController else {
            return .invalidParameter
        }
        
        return MOMControllerAnnounceDiscoverability(momController)
    }

    internal func log(message: String) -> Void {
        NSLog("\(message)")
    }
    
}
