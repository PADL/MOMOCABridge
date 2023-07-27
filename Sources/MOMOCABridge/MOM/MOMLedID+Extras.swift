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

extension MOMLedID: CustomStringConvertible {
    static func allCases() -> AnySequence<MOMLedID> {
        AnySequence {
            MOMLedIDGenerator(max: MOMLedID.layer)
        }
    }

    private struct MOMLedIDGenerator: IteratorProtocol {
        var currentKeyID = MOMLedID.output1.rawValue // 1
        var maximumLedID: Int

        init(max: MOMLedID) {
            maximumLedID = max.rawValue
        }

        mutating func next() -> MOMLedID? {
            if currentKeyID > maximumLedID {
                return nil
            }

            let item = MOMLedID(rawValue: currentKeyID)

            currentKeyID += 1

            return item
        }
    }

    init?(keyID: MOMKeyID) {
        guard keyID != .external else {
            return nil
        }
        self.init(rawValue: keyID.rawValue)
    }

    var keyID: MOMKeyID {
        MOMKeyID(rawValue: rawValue)!
    }

    public var description: String {
        keyID.description
    }
}
