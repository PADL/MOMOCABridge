//
//  RotaryEncoder.swift
//  MOM
//
//  Created by Luke Howard on 24.05.18.
//  Copyright © 2018 PADL Software Pty Ltd. All rights reserved.
//

import Foundation

struct RotaryEncoder {
    private static let Steps = MOM.dBTotalGain * MOM.dBIncrements
    
    private(set) internal var rotationCount: UInt16 = 0
    
    private static func unscale(_ value: Float) -> Int {
        precondition(value >= 0.0)
        precondition(value <= 1.0)
        
        return lroundf(value.squareRoot() * Float(RotaryEncoder.Steps))
    }
    
    internal mutating func rotate(by steps: Int) -> Void {
        if steps > 0 {
            self.rotationCount = self.rotationCount &+ UInt16(steps.magnitude)
        } else {
            self.rotationCount = self.rotationCount &- UInt16(steps.magnitude)
        }
    }
    
    private mutating func rotate(to newValue: Int, from oldValue: Int) -> Void {
        rotate(by: newValue - oldValue)
    }
    
    internal mutating func rotateScaled(to newValue: Float, from oldValue: Float) -> Void {
        let oldValueUnscaled = RotaryEncoder.unscale(oldValue)
        let newValueUnscaled = RotaryEncoder.unscale(newValue)
        
        rotate(to: newValueUnscaled, from: oldValueUnscaled)
    }
}
