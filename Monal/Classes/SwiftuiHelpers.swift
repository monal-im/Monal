//
//  ContactDetailsInterface.swift
//  Monal
//
//  Created by Jan on 22.10.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

import Foundation
import SwiftUI
import PhotosUI
import monalxmpp
import Combine
import CocoaLumberjack

typealias monal_void_block_t = @convention(block) () -> Void;
typealias monal_id_block_t = @convention(block) (AnyObject?) -> Void;

let monalGreen = Color(UIColor(red:128.0/255, green:203.0/255, blue:182.0/255, alpha:1.0));
let monalDarkGreen = Color(UIColor(red:20.0/255, green:138.0/255, blue:103.0/255, alpha:1.0));

let swiftuiTranslationDummyString = Text("Dummy string to test SwiftUI translation support.")

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

//see https://www.hackingwithswift.com/books/ios-swiftui/importing-an-image-into-swiftui-using-phpickerviewcontroller
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {

    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let provider = results.first?.itemProvider else { return }

            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    self.parent.image = image as? UIImage
                }
            }
        }
    }
}

// clear button for text fields, see https://stackoverflow.com/a/58896723/3528174
struct ClearButton: ViewModifier {
    @Binding var text: String
    public func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            content
            if(!text.isEmpty) {
                Button(action: {
                    self.text = ""
                }) {
                    Image(systemName: "delete.left")
                    .foregroundColor(Color(UIColor.opaqueSeparator))
                }
                .padding(.trailing, 8)
            }
        }
    }
}
//this extension contains the easy-access view modifier
extension View {
    func addClearButton(text: Binding<String>) -> some View {
        modifier(ClearButton(text:text))
    }
}

// lazy loading of views (e.g. when used inside a NavigationLink) with the additional ability to use a closure to modify/wrap them
// see https://stackoverflow.com/a/61234030/3528174
struct LazyClosureView<Content: View>: View {
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

// use this to wrap a view into NavigationView, if it should be the outermost swiftui view of a new view stack
struct AddTopLevelNavigation<Content: View>: View {
    let build: () -> Content
    let delegate: SheetDismisserProtocol
    init(withDelegate delegate: SheetDismisserProtocol, to build: @autoclosure @escaping () -> Content) {
        self.build = build
        self.delegate = delegate
    }
    init(withDelegate delegate: SheetDismisserProtocol, andClosure build: @escaping () -> Content) {
        self.build = build
        self.delegate = delegate
    }
    var body: some View {
        NavigationView {
            build()
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarBackButtonHidden(true) // will not be shown because swiftui does not know we navigated here from UIKit
            .navigationBarItems(leading: Button(action : {
                self.delegate.dismiss()
            }){
                Image(systemName: "arrow.backward")
            }.keyboardShortcut(.escape, modifiers: []))
        }
        .navigationViewStyle(.stack)
    }
}

// TODO: fix those workarounds as soon as we have no storyboards anymore
struct UIKitWorkaround<Content: View>: View {
    let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) {
        self.build = build
    }
    init(withClosure build: @escaping () -> Content) {
        self.build = build
    }
    var body: some View {
        if(UIDevice.current.userInterfaceIdiom == .phone) {
            build().navigationBarTitleDisplayMode(.inline)
        } else {
#if targetEnvironment(macCatalyst)
            build().navigationBarTitleDisplayMode(.inline)
#else
            NavigationView {
                build()
                .navigationBarTitleDisplayMode(.automatic)
            }
            .navigationViewStyle(.stack)

#endif
        }
    }
}

// Alert properties for use in Alert
struct AlertPrompt {
    var title: Text = Text("")
    var message: Text = Text("")
    var dismissLabel: Text = Text("Close")
}

// Interfaces between ObjectiveC/Storyboards and SwiftUI
@objc
class SwiftuiInterface : NSObject {
    @objc
    func makeContactDetails(_ contact: MLContact) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        delegate.host = host
        host.rootView = AnyView(AddTopLevelNavigation(withDelegate:delegate, to:ContactDetails(delegate:delegate, contact:ObservableKVOWrapper<MLContact>(contact))))
        return host
    }
    
    @objc
    func makeOwnOmemoKeyView(_ ownContact: MLContact?) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        delegate.host = host
        if(ownContact == nil) {
            host.rootView = AnyView(OmemoKeys(contact: nil))
        } else {
            host.rootView = AnyView(OmemoKeys(contact: ObservableKVOWrapper<MLContact>(ownContact!)))
        }
        return host
    }
    
    @objc
    func makeAccountRegistration(_ registerData: [String:AnyObject]?) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        delegate.host = host
        host.rootView = AnyView(AddTopLevelNavigation(withDelegate:delegate, to:RegisterAccount(delegate:delegate, registerData:registerData)))
        return host
    }
    
    @objc
    func makePasswordMigration(_ needingMigration: [[String:NSObject]]) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        delegate.host = host
        host.rootView = AnyView(AddTopLevelNavigation(withDelegate:delegate, to:PasswordMigration(delegate:delegate, needingMigration:needingMigration)))
        return host
    }
    
    @objc
    func makeBackgroundSettings(_ contact: MLContact?) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        delegate.host = host
        var contactArg:ObservableKVOWrapper<MLContact>? = nil;
        if let contact = contact {
            contactArg = ObservableKVOWrapper<MLContact>(contact)
        }
        host.rootView = AnyView(UIKitWorkaround(BackgroundSettings(contact:contactArg, delegate:delegate)))
        return host
    }

    @objc
    func makeAddContactView(dismisser: @escaping (MLContact) -> ()) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        delegate.host = host
        host.rootView = AnyView(AddTopLevelNavigation(withDelegate: delegate, to: AddContactMenu(delegate: delegate, dismissWithNewContact: dismisser)))
        return host
    }

    @objc
    func makeView(name: String) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        delegate.host = host
        switch(name) { // TODO names are currently taken from the segue identifier, an enum would be nice once everything is ported to SwiftUI
            case "NotificationSettings":
                host.rootView = AnyView(UIKitWorkaround(NotificationSettings(delegate:delegate)))
            case "WelcomeLogIn":
                host.rootView = AnyView(AddTopLevelNavigation(withDelegate:delegate, to:WelcomeLogIn(delegate:delegate)))
            case "LogIn":
                host.rootView = AnyView(UIKitWorkaround(WelcomeLogIn(delegate:delegate)))
            case "ContactRequests":
                host.rootView = AnyView(AddTopLevelNavigation(withDelegate: delegate, to: ContactRequestsMenu(delegate: delegate)))
            default:
                assert(false, "unreachable"); // TODO port unreachable macro to swift
        }
        return host
    }
}

func getContactList(viewContact: (ObservableKVOWrapper<MLContact>?)) -> [ObservableKVOWrapper<MLContact>] {
    if let contact = viewContact {
        if(contact.isGroup && contact.mucType == "group") {
            //this uses the account the muc belongs to and treats every other account to be remote, even when multiple accounts of the same monal instance are in the same group
            let jidList = Array(DataLayer.sharedInstance().getMembersAndParticipants(ofMuc: contact.contactJid, forAccountId: contact.accountId))
            var contactList : [ObservableKVOWrapper<MLContact>] = []
            for jidDict in jidList {
                //jid can be participant_jid (if currently joined to muc) or member_jid (if not joined but member of muc)
                var jid : String? = jidDict["participant_jid"] as? String
                if(jid == nil) {
                    jid = jidDict["member_jid"] as? String
                }
                if(jid != nil) {
                    let contact = MLContact.createContact(fromJid: jid!, andAccountNo: contact.accountId)
                    contactList.append(ObservableKVOWrapper<MLContact>(contact))
                }
            }
            return contactList
        } else {
            return [contact]
        }
    } else {
        return []
    }
}
