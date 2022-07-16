//
//  ContactDetails.swift
//  Monal
//
//  Created by Jan on 22.10.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

import UIKit
import SwiftUI
import monalxmpp

struct ContactDetails: View {
    var delegate: SheetDismisserProtocol
    @StateObject var contact: ObservableKVOWrapper<MLContact>
    @State private var showingBlockContactConfirmation = false
    @State private var showingCannotBlockAlert = false
    @State private var showingRemoveContactConfirmation = false
    @State private var showingAddContactConfirmation = false
    @State private var showingClearHistoryConfirmation = false
    @State private var showingResetOmemoSessionConfirmation = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading) {
                        //header
                        ContactDetailsHeader(contact: contact)
                        Spacer().frame(height: 20)
                    }
                }.padding()
                    
                // info/nondestructive buttons
                Section {
                    if(!contact.isGroup) {
                        TextField("Change Nickname", text: $contact.nickNameView)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .modifier(ClearButton(text: $contact.nickNameView))
                    }
                    
                    Button(contact.isPinned ? "Unpin Chat" : "Pin Chat") {
                        contact.obj.togglePinnedChat(!contact.isPinned);
                    }
#if !DISABLE_OMEMO
                    if(contact.isGroup == false) {
                        NavigationLink(destination: NavigationLazyView(OmemoKeys(contact: contact))) {
                            Text("Encryption Keys")
                        }
                    } else if(contact.isGroup && contact.mucType == "group") {
                        NavigationLink(destination: NavigationLazyView(OmemoKeys(contact: contact))) {
                            Text("Encryption Keys")
                        }
                    }
#endif
                    
                    if(!contact.isGroup) {
                        NavigationLink(destination: NavigationLazyView(ContactResources(contact: contact))) {
                            Text("Resources")
                        }
                    }
                }

                Section { // the destructive section...
                    Button(action: {
                        if(!contact.isBlocked) {
                            showingBlockContactConfirmation = true
                        } else {
                            showingCannotBlockAlert = !contact.obj.toggleBlocked(!contact.isBlocked)
                        }
                    }) {
                        if(!contact.isBlocked) {
                            Text("Block Contact")
                                .foregroundColor(.red)
                        } else {
                            Text("Unblock Contact")
                        }
                    }
                    .alert(isPresented: $showingCannotBlockAlert) {
                        Alert(title: Text("Blocking/Unblocking Not Supported"), message: Text("The server does not support blocking (XEP-0191)."), dismissButton: .default(Text("Close")))
                    }
                    .actionSheet(isPresented: $showingBlockContactConfirmation) {
                        ActionSheet(
                            title: Text("Block Contact"),
                            message: Text("Do you really want to block this contact? You won't receive any messages from this contact."),
                            buttons: [
                                .cancel(),
                                .destructive(
                                    Text("Yes"),
                                    action: {
                                        showingCannotBlockAlert = !contact.obj.toggleBlocked(!contact.isBlocked)
                                    }
                                )
                            ]
                        )
                    }

                    Group {
                        if(contact.isInRoster) {
                            Button(action: {
                                showingRemoveContactConfirmation = true
                            }) {
                                if(contact.isGroup) {
                                    if(contact.mucType == "group") {
                                        Text("Leave Group")
                                            .foregroundColor(.red)
                                    } else {
                                        Text("Leave Channel")
                                            .foregroundColor(.red)
                                    }
                                } else {
                                    Text("Remove from contacts")
                                        .foregroundColor(.red)
                                }
                            }
                            .actionSheet(isPresented: $showingRemoveContactConfirmation) {
                                ActionSheet(
                                    title: Text(contact.isGroup ? NSLocalizedString("Leave this conversation", comment: "") : String(format: NSLocalizedString("Remove %@ from contacts?", comment: ""), contact.contactJid)),
                                        message: Text(contact.isGroup ? NSLocalizedString("You will no longer receive messages from this conversation", comment: "") : NSLocalizedString("They will no longer see when you are online. They may not be able to send you encrypted messages.", comment: "")),
                                    buttons: [
                                        .cancel(),
                                        .destructive(
                                            Text("Yes"),
                                            action: {
                                                contact.obj.removeFromRoster()      //this will dismiss the chatview via kMonalContactRemoved notification
                                                self.delegate.dismiss()
                                            }
                                        )
                                    ]
                                )
                            }
                        } else {
                            Button(action: {
                                showingAddContactConfirmation = true
                            }) {
                                if(contact.isGroup) {
                                    if(contact.mucType == "group") {
                                        Text("Join Group")
                                    } else {
                                        Text("Join Channel")
                                    }
                                } else {
                                    Text("Add to contacts")
                                }
                            }
                            .actionSheet(isPresented: $showingAddContactConfirmation) {
                                ActionSheet(
                                    title: Text(contact.isGroup ? (contact.mucType == "group" ? NSLocalizedString("Join Group", comment: "") : NSLocalizedString("Join Channel", comment: "")) : String(format: NSLocalizedString("Add %@ to your contacts?", comment: ""), contact.contactJid)),
                                    message: Text(contact.isGroup ? NSLocalizedString("You will receive subsequent messages from this conversation", comment: "") : NSLocalizedString("They will see when you are online. They will be able to send you encrypted messages.", comment: "")),
                                    buttons: [
                                        .cancel(),
                                        .default(
                                            Text("Yes"),
                                            action: {
                                                contact.obj.addToRoster()
                                            }
                                        ),
                                    ]
                                )
                            }
                        }
                    }

                    Button(action: {
                        showingClearHistoryConfirmation = true
                    }) {
                        if(contact.isGroup) {
                            Text("Clear chat history of this group")
                        } else {
                            Text("Clear chat history of this contact")
                        }
                    }
                    .foregroundColor(.red)
                    .actionSheet(isPresented: $showingClearHistoryConfirmation) {
                        ActionSheet(
                            title: Text("Clear History"),
                            message: Text("Do you really want to clear all messages exchanged in this conversation? If using OMEMO you won't even be able to load them from your server again."),
                            buttons: [
                                .cancel(),
                                .destructive(
                                    Text("Yes"),
                                    action: {
                                        contact.obj.clearHistory()
                                    }
                                )
                            ]
                        )
                    }
                }

#if !DISABLE_OMEMO
                //even more buttons
                Section {
                    // only display omemo session reset button on 1:1 and private groups
                    if(contact.obj.isGroup == false || (contact.isGroup && contact.mucType == "group"))
                    {
                        Button(action: {
                            showingResetOmemoSessionConfirmation = true
                        }) {
                            Text("Reset OMEMO session")
                                .foregroundColor(.red)
                        }
                        .actionSheet(isPresented: $showingResetOmemoSessionConfirmation) {
                            ActionSheet(
                                title: Text("Reset OMEMO session"),
                                message: Text("Do you really want to reset the OMEMO session? You should only reset the connection if you know what you are doing!"),
                                buttons: [
                                    .cancel(),
                                    .destructive(
                                        Text("Yes"),
                                        action: {
                                            contact.obj.resetOmemoSession()
                                        }
                                    )
                                ]
                            )
                        }
                    }
                }
#endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationBarBackButtonHidden(true)                   // will not be shown because swiftui does not know we navigated here from UIKit
            .navigationBarItems(leading: Button(action : {
                self.delegate.dismiss()
            }){
                Image(systemName: "arrow.backward")
            }.keyboardShortcut(.escape, modifiers: []))
            .navigationBarTitle(contact.contactDisplayName as String, displayMode: .inline)
        }
        .navigationViewStyle(.stack)
    }
}

/* struct Resources: UIViewControllerRepresentable {
    @ObservedObject var contact: ObservableKVOWrapper<MLContact>
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = MLResourcesTableViewController()
        controller.contact = self.contact.obj
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    }
}*/


struct ContactDetails_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        ContactDetails(delegate:delegate, contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(0)))
        ContactDetails(delegate:delegate, contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(1)))
        ContactDetails(delegate:delegate, contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(2)))
        ContactDetails(delegate:delegate, contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(3)))
        ContactDetails(delegate:delegate, contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(4)))
    }
}
