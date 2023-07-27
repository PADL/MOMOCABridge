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

extension MOMKeyID: CustomStringConvertible {
    static func allLabelableCases() -> AnySequence<MOMKeyID> {
        AnySequence {
            MOMKeyIDGenerator(max: MOMKeyID.sourceC)
        }
    }

    static func allCases() -> AnySequence<MOMKeyID> {
        AnySequence {
            MOMKeyIDGenerator(max: MOMKeyID.layer)
        }
    }

    private struct MOMKeyIDGenerator: IteratorProtocol {
        var currentKeyID = MOMKeyID.output1.rawValue // 1
        var maximumKeyID: Int

        init(max: MOMKeyID) {
            maximumKeyID = max.rawValue
        }

        mutating func next() -> MOMKeyID? {
            if currentKeyID > maximumKeyID {
                return nil
            }

            let item = MOMKeyID(rawValue: currentKeyID)

            currentKeyID += 1

            return item
        }
    }

    var labelSuffix: String {
        switch self {
        case .output1: return "Output1"
        case .output2: return "Output2"
        case .output3: return "Output3"
        case .sourceA: return "SourceA"
        case .sourceB: return "SourceB"
        case .sourceC: return "SourceC"
        case .ref: return "Ref"
        case .dim: return "Dim"
        case .talk: return "Talkback"
        case .cut: return "Cut"
        case .layer: return "Layer"
        case .external: return "External"
        }
    }

    public var description: String {
        labelSuffix
    }

    init(ledID: MOMLedID) {
        self.init(rawValue: ledID.rawValue)!
    }

    var ledID: MOMLedID? {
        guard self != .external else { return nil }
        return MOMLedID(rawValue: rawValue)
    }
}

extension MOMKeyID: Codable {}
