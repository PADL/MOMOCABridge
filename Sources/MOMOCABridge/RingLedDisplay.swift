//
//  RingLedDisplay.swift
//  MOM
//
//  Created by Luke Howard on 24.05.18.
//  Copyright © 2018 PADL Software Pty Ltd. All rights reserved.
//

import Foundation

struct RingLedDisplay {
    enum LedColor : Int {
        case off = 0, green, red, orange
    }

    // lookup table enumerates the states a LED pair can be
    private static let LedLut = [
        ( LedColor.red,    LedColor.off     ),
        ( LedColor.orange, LedColor.green   ),
        ( LedColor.orange, LedColor.orange  ),
        ( LedColor.green,  LedColor.orange  ),
        ]
    internal static let LedCount = 27
    internal static let LedSteps = (LedCount - 1) * LedLut.count
    
    private var ledState = [LedColor](repeating: LedColor.off, count: LedCount)

    // this returns an optional as there are some invalid states whilst the
    // virtual ring led display is being updated which should be ignored
    internal var value: Int? {
        var interpolatedValue : Int? = nil
        
        for i in 0 ... ledState.count - 1 {
            var ringLedPair = ( ledState[i], i == ledState.count - 1 ? LedColor.off : ledState[i + 1] )
            
            if i == 0 && ringLedPair.0 == LedColor.orange && ringLedPair.1 == LedColor.off {
                ringLedPair.0 = LedColor.red // Orange is the new Red
            }
            
            if let lutIndex = RingLedDisplay.LedLut.firstIndex(where: { $0 == ringLedPair }) {
                interpolatedValue = i * RingLedDisplay.LedLut.count + lutIndex
                break
            }
        }
        
        return interpolatedValue
    }
    
    internal func scaleValue(dB: Float, relativeTo: Float = MOM.dBDadDisplayFloor) -> Float {
        return powf(((dB - relativeTo) / MOM.dBTotalGain), 2.0)
    }
    
    internal var scaledValue: Float? {
        // DADman allows gain control of -100...+12dB, although only -40...+12dB is
        // represented on the ring led display.
        //
        // In other words, a range of 112dB, of which 52dB is representable here
        // (each of the 104 LED positions thus represents a 0.5dB increment)
        if let interpolatedValue = self.value {
            let dB = MOM.dBUnrepresentableGain + Float(interpolatedValue) / MOM.dBIncrements
            
            // scaled to match DADman slider. at least in theory
            return scaleValue(dB: dB, relativeTo: 0.0)
        }
        
        return nil
    }
    
    internal var dBValue: Float? {
        if let interpolatedValue = self.value {
            return MOM.dBMomDisplayFloor + Float(interpolatedValue) / MOM.dBIncrements
        }
        
        return nil
    }
    
    internal mutating func update(led ledNumber: Int, to color: RingLedDisplay.LedColor) -> Void {
        precondition(ledNumber <= RingLedDisplay.LedCount)

        self.ledState[ledNumber - 1] = color
    }

    private static func unscale(_ value: Float) -> Int {
        precondition(value >= 0.0)
        precondition(value <= 1.0)
        
        // converse of scaledValue(), this calculates the number of LED steps
        // from the slider value, clamping unrepresentable values to 0
        var unscaledValue = MOM.dBIncrements * (MOM.dBTotalGain * value.squareRoot() - MOM.dBUnrepresentableGain)
        
        if unscaledValue < 0 {
            unscaledValue = 0
        }
        
        return lroundf(unscaledValue)
    }
    
    internal static func colorForScaledValue(led ledNumber: Int, value: Float) -> RingLedDisplay.LedColor {
        precondition(ledNumber <= RingLedDisplay.LedCount)
        
        let interpolatedValue = unscale(value)
        
        if interpolatedValue / ledNumber != 0 {
            let ledIntensity = RingLedDisplay.LedLut[interpolatedValue % RingLedDisplay.LedLut.count]
            
            return ledNumber % 2 != 0 ? ledIntensity.0 : ledIntensity.1
        }
        
        return LedColor.off
    }

    internal func colorForLed(led ledNumber: Int) -> RingLedDisplay.LedColor? {
        guard ledNumber >= 0 && ledNumber < Self.LedCount else {
            return nil
        }
        
        return self.ledState[ledNumber]
    }
}
