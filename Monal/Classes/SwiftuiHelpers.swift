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

    private func addObserverForMember(_ member: String){
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
    }

    subscript<T>(member: String) -> T {
        get {
            addObserverForMember(member)
            DDLogDebug("Returning value for member \(member): \(String(describing:self.obj.value(forKeyPath:member)))")
            return self.obj.value(forKeyPath:member) as! T
        }
        set {
            self.obj.setValue(newValue, forKey:member)
        }
    }
    
    subscript<T>(dynamicMember member: String) -> T {
        get {
            addObserverForMember(member)
            DDLogDebug("Returning value for member \(member): \(String(describing:self.obj.value(forKey:member)))")
            return self.obj.value(forKey:member) as! T
        }
        set {
            self.obj.setValue(newValue, forKey:member)
        }
    }
}

// clear button for text fields, see https://stackoverflow.com/a/58896723/3528174
struct ClearButton: ViewModifier
{
    @Binding var text: String

    public func body(content: Content) -> some View
    {
        ZStack(alignment: .trailing)
        {
            content
            if !text.isEmpty
            {
                Button(action:
                {
                    self.text = ""
                })
                {
                    Image(systemName: "delete.left")
                        .foregroundColor(Color(UIColor.opaqueSeparator))
                }
                .padding(.trailing, 8)
            }
        }
    }
}

// lazy loading of navigation destination views, see https://stackoverflow.com/a/61234030/3528174
struct NavigationLazyView<Content: View>: View {
    let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    init(withClosure build: @escaping () -> Content) {
        self.build = build
    }
    var body: Content {
        build()
    }
}

// Alert properties for use in Alert
struct AlertPrompt {
    var title: String = ""
    var message: String = ""
    var dismissLabel: String = "Close"
}

// Interfaces between ObjectiveC/Storyboards and SwiftUI
@objc
class SwiftuiInterface : NSObject {
    @objc
    func makeContactDetails(_ contact: MLContact) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let details = ContactDetails(delegate:delegate, contact:ObservableKVOWrapper<MLContact>(contact))
        let host = UIHostingController(rootView:AnyView(details))
        details.delegate.host = host
        return host
    }

    @objc
    func makeView(name: String) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        delegate.host = host
        switch(name) { // TODO names are currently taken from the segue identifier, an enum would be nice once everything is ported to SwiftUI
        case "NotificationSettings":
            host.rootView = AnyView(NotificationSettings(delegate:delegate))
        case "WelcomeLogIn":
            host.rootView = AnyView(WelcomeLogIn(delegate:delegate))
        default:
            assert(false, "unreachable"); // TODO port unreachable macro to swift
        }
        return host
    }
}
