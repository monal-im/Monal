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
@_exported import PromiseKit
import CocoaLumberjackSwiftLogBackend
import LibMonalRustSwiftBridge
import Combine
//needed to render SVG to UIImage
import SwiftUI
import SVGView

//import some defines in MLConstants.h into swift
let kAppGroup = HelperTools.getObjcDefinedValue(.kAppGroup)
let kMonalOpenURL = HelperTools.getObjcDefinedValue(.kMonalOpenURL)
let kBackgroundProcessingTask = HelperTools.getObjcDefinedValue(.kBackgroundProcessingTask)
let kBackgroundRefreshingTask = HelperTools.getObjcDefinedValue(.kBackgroundRefreshingTask)
let kMonalKeychainName = HelperTools.getObjcDefinedValue(.kMonalKeychainName)
let SHORT_PING = HelperTools.getObjcDefinedValue(.SHORT_PING)
let LONG_PING = HelperTools.getObjcDefinedValue(.LONG_PING)
let MUC_PING = HelperTools.getObjcDefinedValue(.MUC_PING)
let BGFETCH_DEFAULT_INTERVAL = HelperTools.getObjcDefinedValue(.BGFETCH_DEFAULT_INTERVAL)

public typealias monal_void_block_t = @convention(block) () -> Void;
public typealias monal_id_block_t = @convention(block) (AnyObject?) -> Void;
public typealias monal_timer_block_t = @convention(block) (MLDelayableTimer?) -> Void;

//see https://stackoverflow.com/a/40629365/3528174
extension String: Error {}

//see https://stackoverflow.com/a/40592109/3528174
public func objcCast<T>(_ obj: Any) -> T {
    return unsafeBitCast(obj as AnyObject, to:T.self)
}

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

@objc public enum NotificationPrivacySettingOption: Int, CaseIterable, RawRepresentable {
    case DisplayNameAndMessage
    case DisplayOnlyName
    case DisplayOnlyPlaceholder
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
public class ObservableKVOWrapper<ObjType:NSObject>: ObservableObject, Hashable, Equatable, CustomStringConvertible, Identifiable {
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
            if let value = self.getWrapper(for:member) as? T {
                return value
            } else {
                HelperTools.throwException(withName:"ObservableKVOWrapperCastingError", reason:"Could not cast member '\(String(describing:member))' to expected type \(String(describing:T.self))", userInfo:[
                    "key": "\(String(describing:member))",
                    "type": "\(String(describing:T.self))",
                ])
            }
        }
        set {
            self.setWrapper(for:member, value:newValue as AnyObject?)
        }
    }

    public subscript<T>(dynamicMember member: String) -> T {
        get {
            if let value = self.getWrapper(for:member) as? T {
                return value
            } else {
                HelperTools.throwException(withName:"ObservableKVOWrapperCastingError", reason:"Could not cast dynamicMember '\(String(describing:member))' to expected type \(String(describing:T.self))", userInfo:[
                    "key": "\(String(describing:member))",
                    "type": "\(String(describing:T.self))",
                ])
            }
        }
        set {
            self.setWrapper(for:member, value:newValue as AnyObject?)
        }
    }
    
    public var description: String {
        return "ObservableKVOWrapper<\(String(describing:self.obj))>"
    }

    @inlinable
    public static func ==(lhs: ObservableKVOWrapper<ObjType>, rhs: ObservableKVOWrapper<ObjType>) -> Bool {
        return lhs.obj.isEqual(rhs.obj)
    }
    
    @inlinable
    public static func ==(lhs: ObservableKVOWrapper<ObjType>, rhs: ObjType) -> Bool {
        return lhs.obj.isEqual(rhs)
    }
    
    @inlinable
    public static func ==(lhs: ObjType, rhs: ObservableKVOWrapper<ObjType>) -> Bool {
        return lhs.isEqual(rhs.obj)
    }
    
    // see https://stackoverflow.com/a/33320737
    @inlinable
    public static func ===(lhs: ObservableKVOWrapper<ObjType>, rhs: ObservableKVOWrapper<ObjType>) -> Bool {
        return lhs.obj === rhs.obj
    }
    
    @inlinable
    public static func ===(lhs: ObservableKVOWrapper<ObjType>, rhs: ObjType) -> Bool {
        return lhs.obj === rhs
    }
    
    @inlinable
    public static func ===(lhs: ObjType, rhs: ObservableKVOWrapper<ObjType>) -> Bool {
        return lhs === rhs.obj
    }

    @inlinable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.obj.hashValue)
    }
}

struct RuntimeError: LocalizedError {
    let description: String

    init(_ description: String) {
        self.description = description
    }

    var errorDescription: String? {
        description
    }
}

//see https://www.avanderlee.com/swift/property-wrappers/
//and https://fatbobman.com/en/posts/adding-published-ability-to-custom-property-wrapper-types/
@propertyWrapper
public struct defaultsDB<Value> {
    private let key: String
    private var container: UserDefaults = HelperTools.defaultsDB()
    
    public init(_ key: String) {
        self.key = key
    }
    
    public var wrappedValue: Value {
        get {
            if let value = container.object(forKey: key) as? Value {
                return value
            } else {
                HelperTools.throwException(withName:"DefaultsDBCastingError", reason:"Could not cast deaultsDB entry '\(String(describing:key))' to expected type \(String(describing: Value.self))", userInfo:[
                    "key": "\(String(describing:key))",
                    "type": "\(String(describing: Value.self))",
                ])
            }
        }
        set {
            container.set(newValue, forKey: key)
            container.synchronize()
        }
    }
    
    public static subscript<OuterSelf: ObservableObject>(
        _enclosingInstance observed: OuterSelf,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<OuterSelf, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<OuterSelf, Self>
    ) -> Value {
        get { observed[keyPath: storageKeyPath].wrappedValue }
        set {
            if let subject = observed.objectWillChange as? ObservableObjectPublisher {
                subject.send()      // Before modifying wrappedValue
                observed[keyPath: storageKeyPath].wrappedValue = newValue
            } else {
                observed[keyPath: storageKeyPath].wrappedValue = newValue
            }
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
    
    //this is wrapped by HelperTools.renderUIImage(fromSVGURL) / [HelperTools renderUIImageFromSVGURL:]
    //because MLChatImageCell wasn't able to import the monalxmpp-Swift bridging header somehow (but importing HelperTools works just fine)
    @available(iOS 16.0, macCatalyst 16.0, *)
    @objc(_renderUIImageFromSVGURL:)
    public static func _renderUIImageFromSVG(url: URL?) -> UIImage? {
        guard let url = url else {
            return nil
        }
        guard let svgView = SVGParser.parse(contentsOf: url)?.toSwiftUI() else {
            return nil
        }
        var image: UIImage? = nil
        HelperTools.dispatchAsync(false, reentrantOn: DispatchQueue.main) {
            if HelperTools.isAppExtension() {
                image = ImageRenderer(content:svgView.scaledToFit().frame(width: 320, height: 200)).uiImage
                DDLogDebug("We are in appex: mirroring SVG image on Y axis...");
                image = HelperTools.mirrorImage(onXAxis:image)
            } else {
                image = ImageRenderer(content:svgView.scaledToFit().frame(width: 1280, height: 960)).uiImage
            }
        }
        return image
    }
    
    //this is wrapped by HelperTools.renderUIImage(fromSVGURL) / [HelperTools renderUIImageFromSVGURL:]
    //because MLChatImageCell wasn't able to import the monalxmpp-Swift bridging header somehow (but importing HelperTools works just fine)
    @available(iOS 16.0, macCatalyst 16.0, *)
    @objc(_renderUIImageFromSVGData:)
    public static func _renderUIImageFromSVG(data: Data?) -> UIImage? {
        guard let data = data else {
            return nil
        }
        guard let svgView = SVGParser.parse(data: data)?.toSwiftUI() else {
            return nil
        }
        var image: UIImage? = nil
        HelperTools.dispatchAsync(false, reentrantOn: DispatchQueue.main) {
            //the uiimage is somehow mirrored at the X-axis when received by appex --> mirror it back
            if HelperTools.isAppExtension() {
                image = ImageRenderer(content:svgView.scaledToFit().frame(width: 320, height: 200)).uiImage
                DDLogDebug("We are in appex: mirroring SVG image on Y axis...");
                image = HelperTools.mirrorImage(onXAxis:image)
            } else {
                image = ImageRenderer(content:svgView.scaledToFit().frame(width: 1280, height: 960)).uiImage
            }
        }
        return image
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
