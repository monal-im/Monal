//
//  SwiftHelpers.swift
//  monalxmpp
//
//  Created by Thilo Molitor on 16.08.23.
//  Copyright © 2023 monal-im.org. All rights reserved.
//

//see https://davedelong.com/blog/2018/01/19/simplifying-swift-framework-development/ for explanation of @_exported
@_exported import Foundation
@_exported import CocoaLumberjackSwift
@_exported import Logging
import CocoaLumberjackSwiftLogBackend
import LibMonalRustSwiftBridge

public typealias monal_void_block_t = @convention(block) () -> Void;
public typealias monal_id_block_t = @convention(block) (AnyObject?) -> Void;

public func unreachable(_ text: String = "unreachable", _ auxData: [String:AnyObject] = [String:AnyObject](), file: String = #file, line: Int = #line, function: String = #function) -> Never {
    DDLogError("unreachable: \(file) \(line) \(function)")
    HelperTools.mlAssert(withText:text, andUserData:auxData, andFile:(file as NSString).utf8String!, andLine:Int32(line), andFunc:(function as NSString).utf8String!)
    while true {}       //should never be reached
}

public func MLAssert(_ predicate: @autoclosure() -> Bool, _ text: String = "", _ auxData: [String:AnyObject] = [String:AnyObject](), file: String = #file, line: Int = #line, function: String = #function) {
    if !predicate() {
        HelperTools.mlAssert(withText:text, andUserData:auxData, andFile:(file as NSString).utf8String!, andLine:Int32(line), andFunc:(function as NSString).utf8String!)
        while true {}       //should never be reached
    }
}

public func nilWrapper(_ value: Any?) -> Any {
    if let value = value {
        return value
    } else {
        return NSNull()
    }
}

public func nilExtractor(_ value: Any?) -> Any? {
    if value is NSNull {
        return nil
    } else {
        return value
    }
}

class KVOObserver: NSObject {
    var obj: NSObject
    var keyPath: String
    var objectWillChange: ()->Void
    
    init(obj:NSObject, keyPath:String, objectWillChange: @escaping ()->Void) {
        self.obj = obj
        self.keyPath = keyPath
        self.objectWillChange = objectWillChange
        super.init()
        self.obj.addObserver(self, forKeyPath: keyPath, options: [], context: nil)
    }
    
    deinit {
        self.obj.removeObserver(self, forKeyPath:self.keyPath)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        //DDLogVerbose("\(String(describing:object)): keyPath \(String(describing:keyPath)) changed: \(String(describing:change))")
        self.objectWillChange()
    }
}

@dynamicMemberLookup
public class ObservableKVOWrapper<ObjType:NSObject>: ObservableObject {
    public var obj: ObjType
    private var observedMembers: NSMutableSet = NSMutableSet()
    private var observers: [KVOObserver] = Array()
    
    public init(_ obj: ObjType) {
        self.obj = obj
    }

    private func addObserverForMember(_ member: String){
        if(!self.observedMembers.contains(member)) {
            DDLogDebug("Adding observer for member '\(member)'...")
            self.observers.append(KVOObserver(obj:self.obj, keyPath:member, objectWillChange: { [weak self] in
                guard let self = self else {
                    return
                }
                //DDLogDebug("Observer said '\(member)' has changed...")
                DispatchQueue.main.async {
                    DDLogDebug("Calling self.objectWillChange.send() for '\(member)'...")
                    self.objectWillChange.send()
                }
            }))
            self.observedMembers.add(member)
        }
    }
    
    private func getWrapper(for member:String) -> AnyObject? {
        addObserverForMember(member)
        //DDLogDebug("Returning value for dynamicMember \(member): \(String(describing:self.obj.value(forKey:member)))")
        return self.obj.value(forKey:member) as AnyObject?
    }
    
    private func setWrapper(for member:String, value:AnyObject?) {
        self.obj.setValue(value, forKey:member)
    }

    public subscript<T>(member: String) -> T {
        get {
            return self.getWrapper(for:member) as! T
        }
        set {
            self.setWrapper(for:member, value:newValue as AnyObject?)
        }
    }
    
    public subscript<T>(dynamicMember member: String) -> T {
        get {
            return self.getWrapper(for:member) as! T
        }
        set {
            self.setWrapper(for:member, value:newValue as AnyObject?)
        }
    }
}

@objcMembers
public class SwiftHelpers: NSObject {
    public static func initSwiftHelpers() {
        // Use CocoaLumberjack as swift-log backend
        LoggingSystem.bootstrapWithCocoaLumberjack(for: DDLog.sharedInstance, defaultLogLevel:Logger.Level.debug)
        // Set rust panic handler to this closure
        setRustPanicHandler({(text: String, backtrace: String) in
            HelperTools.handleRustPanic(withText: text, andBacktrace:backtrace)
        });
    }
}

@objcMembers
public class JingleSDPBridge : NSObject {
    @objc(getJingleStringForSDPString:withInitiator:)
    public static func getJingleStringForSDPString(_ sdp: String, with initiator:Bool) -> String? {
        if let retval = sdp_str_to_jingle_str(sdp, initiator) {
            //trigger_panic()
            //interesting: https://gist.github.com/martinmroz/5905c65e129d22a1b56d84f08b35a0f4 to extract rust string
            //see https://www.reddit.com/r/rust/comments/rqr0aj/swiftbridge_generate_ffi_bindings_between_rust/hqdud0b
            return retval.toString()
        }
        DDLogDebug("Got empty optional from rust!")
        return nil
    }
    
    @objc(getSDPStringForJingleString:withInitiator:)
    public static func getSDPStringForJingleString(_ jingle: String, with initiator:Bool) -> String? {
        if let retval = jingle_str_to_sdp_str(jingle, initiator) {
            //interesting: https://gist.github.com/martinmroz/5905c65e129d22a1b56d84f08b35a0f4 to extract rust string
            //see https://www.reddit.com/r/rust/comments/rqr0aj/swiftbridge_generate_ffi_bindings_between_rust/hqdud0b
            return retval.toString()
        }
        DDLogDebug("Got empty optional from rust!")
        return nil
    }
}
