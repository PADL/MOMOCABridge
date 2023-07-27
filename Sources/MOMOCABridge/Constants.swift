//
//  Constants.swift
//  MOM
//
//  Created by Luke Howard on 26.05.18.
//  Copyright © 2018 PADL Software Pty Ltd. All rights reserved.
//

import Foundation

enum MOM {
    // maximum gain range in DADman (112dB)
    internal static let dBTotalGain: Float = 112.0
    
    // increments of gain display supported by ring LED display/rotary encoder (2)
    internal static let dBIncrements: Float = 2.0
    // gain representable by ring led display (52dB)
    internal static let dBRepresentableGain: Float = Float(RingLedDisplay.LedSteps) / dBIncrements
    // gain unrepresentable by ring led display (60dB)
    internal static let dBUnrepresentableGain: Float = dBTotalGain - dBRepresentableGain
    
    // minimum gain in DADman (-100dB)
    internal static let dBDadDisplayFloor: Float = -100.0
    // maximum gain in DADman (+12dB)
    private static let dBDadDisplayCeiling = dBDadDisplayFloor + dBTotalGain
    
    // minimum gain in MOM (-40dB)
    internal static let dBMomDisplayFloor: Float = dBDadDisplayFloor + dBUnrepresentableGain
    // maximum gain in MOM (+12dB)
    internal static let dBMomDisplayCeiling: Float = dBMomDisplayFloor + dBRepresentableGain
}
