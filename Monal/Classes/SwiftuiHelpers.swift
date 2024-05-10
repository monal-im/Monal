//
//  ContactDetailsInterface.swift
//  Monal
//
//  Created by Jan on 22.10.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

//see https://davedelong.com/blog/2018/01/19/simplifying-swift-framework-development/ for explanation of @_exported
@_exported import Foundation
@_exported import CocoaLumberjack
//@_exported import CocoaLumberjackSwift
@_exported import Logging
@_exported import SwiftUI
@_exported import monalxmpp
import PhotosUI
import Combine
import FLAnimatedImage
import OrderedCollections

extension MLContact : Identifiable {}       //make MLContact be usable in swiftui ForEach clauses

let monalGreen = Color(UIColor(red:128.0/255, green:203.0/255, blue:182.0/255, alpha:1.0));
let monalDarkGreen = Color(UIColor(red:20.0/255, green:138.0/255, blue:103.0/255, alpha:1.0));

//see https://stackoverflow.com/a/62207329/3528174
//and https://www.hackingwithswift.com/forums/100-days-of-swiftui/extending-shapestyle-for-adding-colors-instead-of-extending-color/12324
public extension ShapeStyle where Self == Color {
    static var interpolatedWindowBackground: Color { Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor.systemBackground : UIColor.secondarySystemBackground }) }
    static var background: Color { Color(UIColor.systemBackground) }
    static var secondaryBackground: Color { Color(UIColor.secondarySystemBackground) }
    static var tertiaryBackground: Color { Color(UIColor.tertiarySystemBackground) }
}

extension Binding {
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

extension Binding {
    func bytecount(mappedTo: Double) -> Binding<Double> where Value == UInt {
        Binding<Double>(
            get: { Double(self.wrappedValue) / mappedTo },
            set: { newValue in self.wrappedValue = UInt(newValue * mappedTo) }
        )
    }
}

class SheetDismisserProtocol: ObservableObject {
    weak var host: UIHostingController<AnyView>? = nil
    func dismiss() {
        host?.dismiss(animated: true)
    }
    func dismissWithoutAnimation() {
        host?.dismiss(animated: false)
    }
    func replace<V>(with view: V) where V: View {
        host?.rootView = AnyView(view)
    }
}

func getContactList(viewContact: (ObservableKVOWrapper<MLContact>?)) -> OrderedSet<ObservableKVOWrapper<MLContact>> {
    if let contact = viewContact {
        if(contact.isGroup) {
            //this uses the account the muc belongs to and treats every other account to be remote,
            //even when multiple accounts of the same monal instance are in the same group
            var contactList : OrderedSet<ObservableKVOWrapper<MLContact>> = OrderedSet()
            for memberInfo in Array(DataLayer.sharedInstance().getMembersAndParticipants(ofMuc: contact.contactJid, forAccountId: contact.accountId)) {
                //jid can be participant_jid (if currently joined to muc) or member_jid (if not joined but member of muc)
                guard let jid = memberInfo["participant_jid"] as? String ?? memberInfo["member_jid"] as? String else {
                    continue
                }
                contactList.append(ObservableKVOWrapper<MLContact>(MLContact.createContact(fromJid: jid, andAccountNo: contact.accountId)))
            }
            return contactList
        } else {
            return [contact]
        }
    } else {
        return []
    }
}

func mucAffiliationToString(_ affiliation: String?) -> String {
    if let affiliation = affiliation {
        if affiliation == "owner" {
            return NSLocalizedString("Owner", comment:"muc affiliation")
        } else if affiliation == "admin" {
            return NSLocalizedString("Admin", comment:"muc affiliation")
        } else if affiliation == "member" {
            return NSLocalizedString("Member", comment:"muc affiliation")
        } else if affiliation == "none" {
            return NSLocalizedString("Participant", comment:"muc affiliation")
        } else if affiliation == "outcast" {
            return NSLocalizedString("Blocked", comment:"muc affiliation")
        } else if affiliation == "profile" {
            return NSLocalizedString("Open contact details", comment:"muc members list")
        } else if affiliation == "reinvite" {
            return NSLocalizedString("Invite again", comment:"muc invite")
        }
    }
    return NSLocalizedString("<unknown>", comment:"muc affiliation")
}

//see here for some ideas used herein: https://blog.logrocket.com/adding-gifs-ios-app-flanimatedimage-swiftui/#using-flanimatedimage-with-swift
struct GIFViewer: UIViewRepresentable {
    typealias UIViewType = FLAnimatedImageView
    @Binding var data: Data

    func makeUIView(context: Context) -> FLAnimatedImageView {
        let imageView = FLAnimatedImageView(frame:.zero)
        let animatedImage = FLAnimatedImage(animatedGIFData:data)
        imageView.animatedImage = animatedImage
        //imageView.translatesAutoresizingMaskIntoConstraints = false
        //imageView.contentMode = .scaleAspectFit
        //imageView.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        
//         imageView.translatesAutoresizingMaskIntoConstraints = false
//         imageView.layer.cornerRadius = 24
//         imageView.layer.masksToBounds = true
//         imageView.setContentHuggingPriority(.required, for: .vertical)
//         imageView.setContentHuggingPriority(.required, for: .horizontal)
        
        return imageView
    }

    func updateUIView(_ imageView: FLAnimatedImageView, context: Context) {
        let animatedImage = FLAnimatedImage(animatedGIFData:data)
        imageView.animatedImage = animatedImage
    }
    
    @available(iOS 16.0, macCatalyst 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        guard
            let width = proposal.width,
            let height = proposal.height
        else { return nil }
        return CGSize(width: width, height: height)
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

//see https://stackoverflow.com/a/60452526
class DocumentPickerViewController: UIDocumentPickerViewController {
    private let onDismiss: () -> Void
    private let onPick: (URL) -> ()

    init(supportedTypes: [UTType], onPick: @escaping (URL) -> Void, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        self.onPick = onPick

        super.init(forOpeningContentTypes:supportedTypes, asCopy:true)

        allowsMultipleSelection = false
        delegate = self
    }

    required init?(coder: NSCoder) {
        unreachable("init(coder:) has not been implemented")
    }
}

extension DocumentPickerViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        onPick(urls.first!)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        onDismiss()
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: UIViewControllerRepresentableContext<ActivityViewController>) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ActivityViewController>) {
        
    }
}

// clear button for text fields, see https://stackoverflow.com/a/58896723/3528174
struct ClearButton: ViewModifier {
    let isEditing: Bool
    @Binding var text: String
    
    public func body(content: Content) -> some View {
        HStack {
            content
                .accessibilitySortPriority(2)
            
            if isEditing, !text.isEmpty {
                Button {
                    self.text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                        .accessibilityLabel("Clear text")
                }
                .padding(.trailing, 8)
                .accessibilitySortPriority(1)
            }
        }
    }
}
//this extension contains the easy-access view modifier
extension View {
    /// Puts the view in an HStack and adds a clear button to the right when the text is not empty.
    func addClearButton(isEditing: Bool, text: Binding<String>) -> some View {
        modifier(ClearButton(isEditing: isEditing, text:text))
    }
}

//see https://exyte.com/blog/swiftui-tutorial-popupview-library
struct FrameGetterModifier: ViewModifier {
    @Binding var frame: CGRect
    func body(content: Content) -> some View {
        content
        .background(
            GeometryReader { proxy -> AnyView in
                let rect = proxy.frame(in: .global)
                // This avoids an infinite layout loop
                if rect.integral != self.frame.integral {
                    DispatchQueue.main.async {
                        self.frame = rect
                    }
                }
                return AnyView(EmptyView())
            }
        )
    }
}
extension View { 
    func frameGetter(_ frame: Binding<CGRect>) -> some View {
        modifier(FrameGetterModifier(frame: frame))
    }
}

// //see https://stackoverflow.com/a/68291983
// struct OverflowContentViewModifier: ViewModifier {
//     @State private var contentOverflow: Bool = false
//     func body(content: Content) -> some View {
//         GeometryReader { geometry in
//             content
//             .background(
//                 GeometryReader { contentGeometry in
//                     Color.clear.onAppear {
//                         contentOverflow = contentGeometry.size.height > geometry.size.height
//                     }
//                 }
//             )
//             .wrappedInScrollView(when: contentOverflow)
//         }
//     }
// }
// 
// extension View {
//     @ViewBuilder
//     func wrappedInScrollView(when condition: Bool) -> some View {
//         if condition {
//             ScrollView {
//                 self
//             }
//         } else {
//             self
//         }
//     }
// }
// 
// extension View {
//     func scrollOnOverflow() -> some View {
//         modifier(OverflowContentViewModifier())
//     }
// }

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

extension View {
    /// Applies the given transform.
    ///
    /// Useful for availability branching on view modifiers. Do not branch with any properties that may change during runtime as this will cause errors.
    /// - Parameters:
    ///   - transform: The transform to apply to the source `View`.
    /// - Returns: The view transformed by the transform.
    func applyClosure<Content: View>(@ViewBuilder _ transform: (Self) -> Content) -> some View {
        transform(self)
    }
}

// Interfaces between ObjectiveC/Storyboards and SwiftUI
@objc
class SwiftuiInterface : NSObject {
    @objc(makeAccountPickerForContacts:andCallType:)
    func makeAccountPicker(for contacts: [MLContact], and callType: UInt) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        delegate.host = host
        host.rootView = AnyView(AddTopLevelNavigation(withDelegate:delegate, to:AccountPicker(delegate:delegate, contacts:contacts, callType:MLCallType(rawValue: callType)!)))
        return host
    }
    
    @objc(makeCallScreenForCall:)
    func makeCallScreen(for call: MLCall) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        delegate.host = host
        host.rootView = AnyView(AVCallUI(delegate:delegate, call:call))
        return host
    }
    
    @objc
    func makeContactDetails(_ contact: MLContact) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        delegate.host = host
        host.rootView = AnyView(AddTopLevelNavigation(withDelegate:delegate, to:ContactDetails(delegate:delegate, contact:ObservableKVOWrapper<MLContact>(contact))))
        return host
    }
    
    @objc(makeImageViewerForInfo:)
    func makeImageViewerFor(info:[String:AnyObject]) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        delegate.host = host
        host.rootView = AnyView(try! ImageViewer(delegate:delegate, info:info))
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
    func makeAddContactView(forJid jid:String, preauthToken: String?, prefillAccount: xmpp?, andOmemoFingerprints omemoFingerprints: [NSNumber:Data]?, withDismisser dismisser: @escaping (MLContact) -> ()) -> UIViewController {
        let delegate = SheetDismisserProtocol()
        let host = UIHostingController(rootView:AnyView(EmptyView()))
        delegate.host = host
        host.rootView = AnyView(AddTopLevelNavigation(withDelegate: delegate, to: AddContactMenu(delegate: delegate, dismissWithNewContact: dismisser, prefillJid: jid, preauthToken: preauthToken, prefillAccount: prefillAccount, omemoFingerprints: omemoFingerprints)))
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
            case "DebugView":
                host.rootView = AnyView(UIKitWorkaround(DebugView()))
            case "WelcomeLogIn":
                host.rootView = AnyView(AddTopLevelNavigation(withDelegate:delegate, to:WelcomeLogIn(delegate:delegate)))
            case "LogIn":
                host.rootView = AnyView(UIKitWorkaround(WelcomeLogIn(delegate:delegate)))
            case "ContactRequests":
                host.rootView = AnyView(AddTopLevelNavigation(withDelegate: delegate, to: ContactRequestsMenu(delegate: delegate)))
            case "CreateGroup":
                host.rootView = AnyView(AddTopLevelNavigation(withDelegate: delegate, to: CreateGroupMenu(delegate: delegate)))
            case "ChatPlaceholder":
                host.rootView = AnyView(ChatPlaceholder())
            case "PrivacySettings" :
                host.rootView = AnyView(UIKitWorkaround(PrivacySettings()))
            case "ActiveChatsPrivacySettings":
                host.rootView = AnyView(AddTopLevelNavigation(withDelegate: delegate, to: PrivacySettings()))
            default:
                unreachable()
        }
        return host
    }
}
