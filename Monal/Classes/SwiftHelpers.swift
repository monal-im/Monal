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
@_exported import OrderedCollections
import CocoaLumberjackSwiftLogBackend
import LibMonalRustSwiftBridge
import Combine
//needed to use Binding type
import SwiftUI

public typealias monal_timer_block_t = @convention(block) (MLDelayableTimer?) -> Void;
public typealias monal_void_block_t = @convention(block) () -> Void;
public typealias monal_id_block_t = @convention(block) (AnyObject?) -> Void;
public typealias monal_id_returning_void_block_t = @convention(block) () -> AnyObject?;
public typealias monal_id_returning_id_block_t = @convention(block) (AnyObject?) -> AnyObject?;

extension MLContact : Identifiable {}               //make MLContact be usable in swiftui ForEach clauses etc.
extension Quicksy_Country : Identifiable {}         //make Quicksy_Country be usable in swiftui ForEach clauses etc.

//see https://stackoverflow.com/a/40629365/3528174
extension String: @retroactive Error {}

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

public extension Binding {
    func optionalMappedToBool<Wrapped>() -> Binding<Bool> where Value == Wrapped? {
        Binding<Bool>(
            get: { self.wrappedValue != nil },
            set: { newValue in
                MLAssert(!newValue, "New value should never be true when writing to a binding created by optionalMappedToBool()")
                self.wrappedValue = nil
            }
        )
    }
}
public extension Binding {
    func bytecount(mappedTo: Double) -> Binding<Double> where Value == UInt {
        Binding<Double>(
            get: { Double(self.wrappedValue) / mappedTo },
            set: { newValue in self.wrappedValue = UInt(newValue * mappedTo) }
        )
    }
}

public extension String {
    /**
     Returns an attributed version of the string, where the links are clickable.
     */
    func linkify() -> AttributedString {
        var attributed = AttributedString(self)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(self.startIndex..., in: self)
            detector.enumerateMatches(in: self, range: range) { match, _, _ in
                if let match = match, let url = match.url, let range = Range(match.range, in: attributed) {
                    attributed[range].link = url
                    attributed[range].underlineStyle = .single
                    attributed[range].foregroundColor = Color("monalGreen")
                }
            }
        }
        return attributed
    }
}

@objc public enum NotificationPrivacySettingOption: Int, CaseIterable, RawRepresentable {
    case DisplayNameAndMessage
    case DisplayOnlyName
    case DisplayOnlyPlaceholder
}

final class ChangeCoalescer {
    private var scheduled = false
    private let lock = NSLock()
    private let notify: () -> Void

    init(notify: @escaping () -> Void) {
        self.notify = notify
    }

    func markChanged() {
        lock.lock()
        defer { lock.unlock() }
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async {
            self.lock.lock()
            self.scheduled = false
            self.lock.unlock()
            self.notify()
        }
    }
}

class KVOObserver: NSObject {
    var obj: NSObject
    var keyPath: String
    var coalescer: ChangeCoalescer
    
    init(obj:NSObject, keyPath:String, coalescer: ChangeCoalescer) {
        self.obj = obj
        self.keyPath = keyPath
        self.coalescer = coalescer
        super.init()
        self.obj.addObserver(self, forKeyPath: keyPath, options: [], context: nil)
    }
    
    deinit {
        self.obj.removeObserver(self, forKeyPath:self.keyPath)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        //DDLogVerbose("\(String(describing:object)): keyPath \(String(describing:keyPath)) changed: \(String(describing:change))")
        self.coalescer.markChanged()
    }
}

@dynamicMemberLookup
public class ObservableKVOWrapper<ObjType:NSObject>: ObservableObject, Hashable, Equatable, CustomStringConvertible, Identifiable {
    public let obj: ObjType
    private var observedMembers: NSMutableSet = NSMutableSet()
    private var observers: [KVOObserver] = Array()
    
    private lazy var coalescer = ChangeCoalescer { [weak self] in
        guard let self = self else {
            return
        }
        DDLogDebug("Calling objectWillChange.send() for obj: \(String(describing:self.obj))")
        self.objectWillChange.send()
    }
    
    public init(_ obj: ObjType) {
        self.obj = obj
    }

    private func addObserverForMember(_ member: String) {
        //doesn't work for protocols
        /*
        guard self.obj.responds(to: NSSelectorFromString(member)), self.obj.responds(to: NSSelectorFromString("set\(member.capitalized):")) else {
            HelperTools.throwException(withName:"ObservableKVOWrapperAccessError", reason:"Getter/setter not provided for member '\(String(describing:member))' by underlying objc object \(String(describing:self.obj))", userInfo:[
                "obj": "\(String(describing:self.obj))",
                "member": "\(String(describing:member))",
            ])
            return
        }
        */
        if(!self.observedMembers.contains(member)) {
            let ownAddress = Unmanaged.passUnretained(self).toOpaque()
            let objAddress = Unmanaged.passUnretained(self.obj).toOpaque()
            DDLogDebug("Adding observer for member '\(member)' in KVOObserver \(ownAddress) with wrapped obj \(objAddress)...")
            self.observers.append(KVOObserver(obj:self.obj, keyPath:member, coalescer: self.coalescer))
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

public extension AnyPromise {
    func toTypedGuarantee<T>() -> Guarantee<T> {
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
    
    func toTypedGuarantee() -> Guarantee<Void> {
        return Guarantee<Void> { seal in
            self.done { _ in
                seal(())
            }.catch { error in
                HelperTools.throwException(withName:"AnyPromiseToGuaranteeConversionError", reason:"Uncatched promise error: \(error)", userInfo:[
                    "error": "\(String(describing:error))",
                    "promise": "\(String(describing: self))",
                ])
            }
        }
    }
    
    func toTypedPromise<T>() -> Promise<T> {
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
    
    func toTypedPromise() -> Promise<Void> {
        return Promise<Void> { seal in
            self.done { _ in
                seal.fulfill(())
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
            self.done { value in
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
            self.done { value in
                continuation.resume(returning: value)
            }
        }
    }
}

public extension MainActor {
    @MainActor static func runOnMainThread<T>(action: @MainActor @Sendable () throws -> T) rethrows -> T {
        try action()
    }
}

public extension Actor {
    /// Adds a general `perform` method for any actor to access its isolation domain to perform
    /// multiple operations in one go using the closure.
    @discardableResult
    func performInIsolation<T: Sendable>(_ block: @Sendable (_ actor: isolated Self) throws -> T) async rethrows -> T {
        try block(self)
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
            case .none: unreachable("nil unwrap!")
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
}

// **********************************************
// **************** rust bridges ****************
// **********************************************

fileprivate extension RustVec {
    func intoArray() -> [T] {
        var array: [T] = []
        for _ in 0..<self.len() {
            array.append(self.pop()!)
        }
        return array.reversed()
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

@objcMembers
public class HtmlParserBridge : NSObject {
    var document: MonalHtmlParser
    
    public init(html: String) {
        self.document = MonalHtmlParser(html)
    }
    
    public func select(_ selector: String, attribute: String? = nil) throws -> [String] {
        return self.document.select(selector, attribute).intoArray().map { $0.toString() }
    }
}

@objcMembers
public class XmlParserBridge : NSObject {
    var wrapped: MonalXmlStreamParserWrapper
    var delegate: MLBasePaser
    
    public init(with delegate: MLBasePaser) {
        //never buffer more than 8192 bytes inside the rust parser and limit maximum
        //token length (attribute value, attribute name, element name) to 1024
        self.wrapped = MonalXmlStreamParserWrapper(8192, 1024)
        self.delegate = delegate
    }
    
    @objc(feedData:withLength:)
    public func feed(data chunk: UnsafePointer<UInt8>, length size: Int) {
        do {
            //this is zero-copy
            self.wrapped.feed(UnsafeBufferPointer(start: chunk, count: size))
            var notDoneYet = true
            while notDoneYet {
                switch try self.wrapped.poll() {
                    case .XmlDeclaration(let version):
                        self.delegate.parserDidStartDocument(version.toString())
                    case .Start(let element):
                        let keys: [String] = element.attr_keys!.intoArray().map { $0.toString() }
                        let values: [String] = element.attr_values!.intoArray().map { $0.toString() }
                        MLAssert(keys.count == values.count, "Atrribute vectors coming from rust should have the same sizes!", [
                            "keys": keys as NSArray,
                            "values": values as NSArray,
                        ])
                        var attributes: [String:String] = [:]
                        for i in 0..<keys.count {
                            attributes[keys[i]] = values[i]
                        }
                        self.delegate.parserDidStartElement(element.name.toString(), namespaceURI:element.ns.toString(), attributes:attributes)
                    case .End:
                        self.delegate.parserDidEndInnermostElement()
                    case .Text(let text):
                        self.delegate.parserFoundCharacters(text.toString())
                    case .NeedMoreData:
                        notDoneYet = false
                }
            }
        } catch let err as RustString {
            DDLogError("XML parser returned error: \(err.toString())")
            self.delegate.parserErrorOccurred(err.toString())
        } catch let err {
            DDLogError("XML parser returned UNEXPECTED error: \(String(describing:err))")
            unreachable("xml parser should never return non-string errors!")
        }
    }
}
