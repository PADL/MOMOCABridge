// This source file is part of the Swift.org open source project
//  
// Copyright (c) 2014 - 2016 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//      
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//      

#if !canImport(Darwin)
import CoreFoundation
import Foundation

internal protocol _SwiftBridgeable {
    associatedtype SwiftType
    var _swiftObject: SwiftType { get }
}

internal protocol _NSBridgeable {
    associatedtype NSType
    var _nsObject: NSType { get }
}

extension NSArray : _SwiftBridgeable {
    internal var _cfObject: CFArray { return unsafeBitCast(self, to: CFArray.self) }
    internal var _swiftObject: [AnyObject] { return Array._unconditionallyBridgeFromObjectiveC(self) }
}       
            
extension NSMutableArray {
    internal var _cfMutableObject: CFMutableArray { return unsafeBitCast(self, to: CFMutableArray.self) }
}   

extension CFArray : _NSBridgeable, _SwiftBridgeable {
    internal var _nsObject: NSArray { return unsafeBitCast(self, to: NSArray.self) }
    internal var _swiftObject: Array<AnyObject> { return _nsObject._swiftObject }
}       
        
extension Array : _NSBridgeable {
    internal var _nsObject: NSArray { return _bridgeToObjectiveC() }
    internal var _cfObject: CFArray { return _nsObject._cfObject }
}

extension NSDictionary : _SwiftBridgeable {
    internal var _cfObject: CFDictionary { return unsafeBitCast(self, to: CFDictionary.self) }
    internal var _swiftObject: Dictionary<AnyHashable, Any> { return Dictionary._unconditionallyBridgeFromObjectiveC(self) }
}               
                    
extension NSMutableDictionary {
    internal var _cfMutableObject: CFMutableDictionary { return unsafeBitCast(self, to: CFMutableDictionary.self) }
}       
        
extension CFDictionary : _NSBridgeable, _SwiftBridgeable {
    internal var _nsObject: NSDictionary { return unsafeBitCast(self, to: NSDictionary.self) }
    internal var _swiftObject: [AnyHashable: Any] { return _nsObject._swiftObject }
}   
        
extension Dictionary : _NSBridgeable {
    internal var _nsObject: NSDictionary { return _bridgeToObjectiveC() }
    internal var _cfObject: CFDictionary { return _nsObject._cfObject }
}               

extension NSString : _SwiftBridgeable {
    typealias SwiftType = String
    internal var _cfObject: CFString { return unsafeBitCast(self, to: CFString.self) }
    internal var _swiftObject: String { return String._unconditionallyBridgeFromObjectiveC(self) }
}       
        
extension NSMutableString {
    internal var _cfMutableObject: CFMutableString { return unsafeBitCast(self, to: CFMutableString.self) }
}       
        
extension CFString : _NSBridgeable, _SwiftBridgeable {
    typealias NSType = NSString
    typealias SwiftType = String
    internal var _nsObject: NSType { return unsafeBitCast(self, to: NSString.self) }
    internal var _swiftObject: String { return _nsObject._swiftObject }
}   

extension String : _NSBridgeable {
    typealias NSType = NSString
    typealias CFType = CFString
    internal var _nsObject: NSType { return _bridgeToObjectiveC() }
    internal var _cfObject: CFType { return _nsObject._cfObject }
}       
#endif
