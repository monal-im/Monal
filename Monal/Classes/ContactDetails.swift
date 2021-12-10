//
//  ContactDetails.swift
//  Monal
//
//  Created by Jan on 22.10.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

import SwiftUI
import monalxmpp

struct ContactDetails: View {
    var delegate: SheetDismisserProtocol
    @StateObject var contact: ObservableKVOWrapper<MLContact>
    @State private var showingCannotBlockAlert = false
    @State private var showingRemoveContactConfirmation = false
    @State private var showingAddContactConfirmation = false

    var body: some View {
        NavigationView {
            VStack {
                Spacer()
                    .frame(height: 20)
                ContactDetailsHeader(contact: contact)
                
                Spacer()
                    .frame(height: 20)
                HStack {
                    Spacer().frame(width: 20)
                    TextField("Nickname", text: $contact.nickNameView)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .modifier(ClearButton(text: $contact.nickNameView))
                    Spacer().frame(width: 20)
                }
                
                Spacer()
                    .frame(height: 20)
                Button(contact.isPinned ? "Unpin Chat" : "Pin Chat") {
                    contact.obj.togglePinnedChat(!contact.isPinned);
                }
                
                Spacer()
                    .frame(height: 20)
                Button(contact.isBlocked ? "Unblock Contact" : "Block Contact") {
                    showingCannotBlockAlert = !contact.obj.toggleBlocked(!contact.isBlocked)
                }
                .alert(isPresented: $showingCannotBlockAlert) {
                    Alert(title: Text("Blocking Not Supported"), message: Text("The server does not support blocking (XEP-0191)."), dismissButton: .default(Text("Close")))
                }
                
                Spacer()
                    .frame(height: 20)
                Button(action: {
                    if(contact.isInRoster) {
                        showingRemoveContactConfirmation = true
                    } else {
                        //showingAddContactConfirmation = true
                        contact.obj.addToRoster()
                    }
                }) {
                    if(contact.isGroup) {
                        Text(contact.mucType == "group" ? "Leave Group" : "Leave Channel")
                    } else if(contact.isInRoster) {
                        Text("Remove from contacts")
                    } else {
                        Text("Add to contacts")
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
                                    contact.obj.removeFromRoster()
                                    self.delegate.dismiss()
                                }
                            )
                        ]
                    )
                }
                /*
                .actionSheet(isPresented: $showingAddContactConfirmation) {
                    ActionSheet(
                        title: Text(String(format: NSLocalizedString("Add %@ to your contacts?", comment: ""), contact.contactJid)),
                        message: Text("They will see when you are online. They will be able to send you encrypted messages."),
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
                */
                //Spacer()
            }
            .navigationBarBackButtonHidden(true)                   // will not be shown because swiftui does not know we navigated here from UIKit
            .navigationBarItems(leading: Button(action : {
                self.delegate.dismiss()
            }){
                Image(systemName: "arrow.backward")
            })
            .navigationTitle(contact.contactDisplayName as String)
        }
    }
}

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
