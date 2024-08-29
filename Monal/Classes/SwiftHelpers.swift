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

public typealias monal_timer_block_t = @convention(block) (MLDelayableTimer?) -> Void;
public typealias monal_void_block_t = @convention(block) () -> Void;
public typealias monal_id_block_t = @convention(block) (AnyObject?) -> Void;
public typealias monal_id_returning_void_block_t = @convention(block) () -> AnyObject?;
public typealias monal_id_returning_id_block_t = @convention(block) (AnyObject?) -> AnyObject?;

extension MLContact : Identifiable {}               //make MLContact be usable in swiftui ForEach clauses etc.
extension Quicksy_Country : Identifiable {}         //make Quicksy_Country be usable in swiftui ForEach clauses etc.

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

extension AnyPromise {
    public func toGuarantee<T>() -> Guarantee<T> {
        return Guarantee<T> { seal in
            self.done { value in
                if let value = nilExtractor(value) as? T {
                    seal(value)
                } else {
                    HelperTools.throwException(withName:"AnyPromiseToGuaranteeConversionError", reason:"Could not cast value to type \(String(describing: T.self))", userInfo:[
                        "type": "\(String(describing: T.self))",
                        "value": "\(String(describing:value))",
                        "from_anyPromise": "\(String(describing: self))",
                    ])
                }
            }.catch { error in
                HelperTools.throwException(withName:"AnyPromiseToGuaranteeConversionError", reason:"Uncatched promise error: \(error)", userInfo:[
                    "error": "\(String(describing:error))",
                    "promise": "\(String(describing: self))",
                ])
            }
        }
    }
    
    public func toPromise<T>() -> Promise<T> {
        return Promise<T> { seal in
            self.done { value in
                if let value = nilExtractor(value) as? T {
                    seal.fulfill(value)
                } else {
                    seal.reject(PMKError.invalidCallingConvention)
                }
            }.catch { error in
                seal.reject(error)
            }
        }
    }
}

//since we can not be generic over actors, any new actor we create has to be added here, if we want to use it in conjunction with promises
//see https://forums.swift.org/t/generic-over-global-actor/67304/2
public extension Promise {
    @MainActor
    func asyncOnMainActor() async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            done { value in
                continuation.resume(returning: value)
            }.catch(policy: .allErrors) { error in
                continuation.resume(throwing: error)
            }
        }
    }
}
public extension Guarantee {
    @MainActor
    func asyncOnMainActor() async -> T {
        await withCheckedContinuation { continuation in
            done { value in
                continuation.resume(returning: value)
            }
        }
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
            if let optional = newValue as? OptionalProtocol {
                if optional.isSome() {
                    container.set(newValue, forKey: key)
                } else {
                    container.removeObject(forKey:key)
                }
            } else {
                container.set(newValue, forKey: key)
            }
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

//see https://stackoverflow.com/a/32780793
protocol OptionalProtocol {
    func isSome() -> Bool
    func unwrap() -> Any
}
extension Optional : OptionalProtocol {
    func isSome() -> Bool {
        switch self {
            case .none: return false
            case .some: return true
        }
    }

    func unwrap() -> Any {
        switch self {
            // If a nil is unwrapped it will crash!
            case .none: preconditionFailure("nil unwrap!")
            case .some(let unwrapped): return unwrapped
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
    
    //we use the main actor here, because ImageRenderer needs to run in the main actor
    //(and we don't want to overcomplicate things here by using a Task and returning a Promise)
    @MainActor
    private static func _renderSVG<T: View>(_ svgView: T) -> UIImage? {
        var image: UIImage? = nil
        if HelperTools.isAppExtension() {
            image = ImageRenderer(content:svgView.scaledToFit().frame(width: 320, height: 200)).uiImage
            DDLogDebug("We are in appex: mirroring SVG image on Y axis...");
            image = HelperTools.mirrorImage(onXAxis:image)
        } else {
            image = ImageRenderer(content:svgView.scaledToFit().frame(width: 1280, height: 960)).uiImage
        }
        return image
    }
    
    //this is wrapped by HelperTools.renderUIImage(fromSVGURL) / [HelperTools renderUIImageFromSVGURL:]
    //because MLChatImageCell wasn't able to import the monalxmpp-Swift bridging header somehow (but importing HelperTools works just fine)
    @objc(_renderUIImageFromSVGURL:)
    public static func _renderUIImageFromSVG(url: URL?) -> AnyPromise {
        return AnyPromise(Promise<UIImage?> { seal in
            guard let url = url, let svgView = SVGParser.parse(contentsOf: url)?.toSwiftUI() else {
                return seal.fulfill(nil)
            }
            Task {
                return seal.fulfill(await self._renderSVG(svgView))
            }
        })
    }
    
    //this is wrapped by HelperTools.renderUIImage(fromSVGURL) / [HelperTools renderUIImageFromSVGURL:]
    //because MLChatImageCell wasn't able to import the monalxmpp-Swift bridging header somehow (but importing HelperTools works just fine)
    @objc(_renderUIImageFromSVGData:)
    public static func _renderUIImageFromSVG(data: Data?) -> AnyPromise {
        return AnyPromise(Promise<UIImage?> { seal in
            guard let data = data, let svgView = SVGParser.parse(data: data)?.toSwiftUI() else {
                return seal.fulfill(nil)
            }
            Task {
                return seal.fulfill(await self._renderSVG(svgView))
            }
        })
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

extension UIImage {
    public func thumbnail(size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
