//
//  ContactDetailsInterface.swift
//  Monal
//
//  Created by Jan on 22.10.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

import Foundation
import SwiftUI
import monalxmpp
import Combine
import CocoaLumberjack

class SheetDismisserProtocol: ObservableObject {
    weak var host: UIHostingController<AnyView>? = nil
    func dismiss() {
        host?.dismiss(animated: true)
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
        self.objectWillChange()
    }
}

@dynamicMemberLookup
class ObservableKVOWrapper<ObjType:NSObject>: ObservableObject {
    public var obj: ObjType
    private var observedMembers: NSMutableSet = NSMutableSet()
    private var observers: [KVOObserver] = Array()
    
    init(_ obj: ObjType) {
        self.obj = obj
    }
    
    subscript<T>(dynamicMember member: String) -> T {
        if(!self.observedMembers.contains(member)) {
            DDLogDebug("Adding observer for member \(member)")
            self.observers.append(KVOObserver(obj:self.obj, keyPath:member, objectWillChange: {
                DDLogDebug("Observer said \(member) has changed")
                DispatchQueue.main.async {
                    DDLogDebug("Calling self.objectWillChange.send()...")
                    self.objectWillChange.send()
                }
            }))
            self.observedMembers.add(member)
        }
        DDLogDebug("Returning value for member \(member): \(self.obj.value(forKey:member) as! T)")
        return self.obj.value(forKey:member) as! T
    }
}

@objc
class ContactDetailsInterface: NSObject {
    @objc
    func makeContactDetails(_ contact: MLContact) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let details = ContactDetails(delegate:delegate, contact:ObservableKVOWrapper<MLContact>(contact))
        //let details = ContactDetails(delegate:delegate, contact:contact)
        let host = UIHostingController(rootView:AnyView(details))
        details.delegate.host = host
        return host
    }
}
