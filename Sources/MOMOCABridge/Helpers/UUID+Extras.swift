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

extension UUID {
    var base64String: String {
        var buffer = [UInt8](repeating: 0, count: 16)

        (self as NSUUID).getBytes(&buffer)

        let data = NSData(bytes: &buffer, length: buffer.count)
        let base64 = data.base64EncodedString(options: NSData.Base64EncodingOptions())

        return base64.replacingOccurrences(of: "=", with: "")
    }

    // https://gist.github.com/xsleonard/b28573142215e25858bebb9ba907829c
    static func from(data: Data?) -> UUID? {
        guard data?.count == MemoryLayout<uuid_t>.size else {
            return nil
        }
        return data?.withUnsafeBytes {
            guard let baseAddress = $0.bindMemory(to: UInt8.self).baseAddress else {
                return nil
            }
            return NSUUID(uuidBytes: baseAddress) as UUID
        }
    }

    static func from(hexString: String) -> UUID? {
        UUID.from(data: Data(hex: hexString))
    }

    var data: Data {
        withUnsafeBytes(of: uuid) { Data($0) }
    }

    var hexString: String {
        data.toHexString()
    }

    static var nullUUID: UUID {
        NSUUID(uuidBytes: [UInt8](repeating: 0, count: 16)) as UUID
    }

    static var platformUUID: UUID? {
        #if canImport(Darwin)
        let platformExpertDevice = IOServiceMatching("IOPlatformExpertDevice")
        let platformExpert: io_service_t = IOServiceGetMatchingService(
            kIOMasterPortDefault,
            platformExpertDevice
        )
        defer { IOObjectRelease(platformExpert) }

        let serialNumberAsCFString = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )
        guard let serialNumberUUIDString = serialNumberAsCFString?.takeRetainedValue() as? String
        else {
            return nil
        }

        return Self(uuidString: serialNumberUUIDString)
        #else
        return nullUUID
        #endif
    }
}
