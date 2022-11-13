//
//  ContactDetailsHeader.swift
//  ContactDetailsHeader
//
//  Created by Friedrich Altheide on 03.09.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

import MobileCoreServices
import SwiftUI
import monalxmpp

struct ContactDetailsHeader: View {
    @StateObject var contact: ObservableKVOWrapper<MLContact>
    @State private var showingCannotEncryptAlert = false
    @State private var showingShouldDisableEncryptionAlert = false

    var body: some View {
        VStack {
            Image(uiImage: contact.avatar)
                .resizable()
                .frame(minWidth: 100, idealWidth: 150, maxWidth: 200, minHeight: 100, idealHeight: 150, maxHeight: 200, alignment: .center)
                .scaledToFit()
                .shadow(radius: 7)
            
            Spacer()
                .frame(height: 20)
            HStack {
                Text(contact.contactJid as String)
                //for ios >= 15.0
                //.textSelection(.enabled)
                Spacer().frame(width: 10)
                Button(action: {
                    UIPasteboard.general.setValue(contact.contactJid as String, forPasteboardType: kUTTypeUTF8PlainText as String)
                }) {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.primary)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
            //only show account jid if more than one is configured
            if MLXMPPManager.sharedInstance().connectedXMPP.count > 1 {
                Text("Account: \(MLXMPPManager.sharedInstance().getConnectedAccount(forID:contact.accountId)!.connectionProperties.identity.jid)")
            }
            
            Spacer()
                .frame(height: 20)
            if(!contact.isGroup) {
                if((contact.lastInteractionTime as Date).timeIntervalSince1970 > 0) {
                    Text(String(format: NSLocalizedString("Last seen: %@", comment: ""),
                        DateFormatter.localizedString(from: contact.lastInteractionTime, dateStyle: DateFormatter.Style.short, timeStyle: DateFormatter.Style.short)))
                } else {
                    Text(String(format: NSLocalizedString("Last seen: %@", comment: ""), NSLocalizedString("now", comment: "")))
                }
            }
            
            Spacer()
                .frame(height: 20)
            HStack {
                Spacer()
                Button(action: {
                    if(contact.isGroup) {
                        if(!contact.isMuted && !contact.isMentionOnly) {
                            contact.obj.toggleMentionOnly(true)
                        } else if(!contact.isMuted && contact.isMentionOnly) {
                            contact.obj.toggleMentionOnly(false)
                            contact.obj.toggleMute(true)
                        } else {
                            contact.obj.toggleMentionOnly(false)
                            contact.obj.toggleMute(false)
                        }
                    } else {
                        contact.obj.toggleMute(!contact.isMuted)
                    }
                }) {
                    if(contact.isMuted) {
                        Image(systemName: "bell.slash.fill")
                    } else if(contact.isGroup && contact.isMentionOnly) {
                        Image(systemName: "bell.badge")
                    } else {
                        Image(systemName: "bell.fill")
                    }
                }
                .buttonStyle(BorderlessButtonStyle())

#if IS_ALPHA                 
                Spacer().frame(width: 20)
                NavigationLink(destination: LazyClosureView(AVPrototype(contact: contact))) {
                    Label("Call", systemImage:"phone")
                }
#endif

                /*
                Spacer().frame(width: 20)
                Button(action: {
                    print("button pressed")
                }) {
                    Image(systemName: "phone")
                }
                */
#if !DISABLE_OMEMO
                if(!contact.isGroup || (contact.isGroup && contact.mucType == "group")) {
                    Spacer().frame(width: 20)
                    Button(action: {
                        if(contact.isEncrypted) {
                            showingShouldDisableEncryptionAlert = true
                        } else {
                            showingCannotEncryptAlert = !contact.obj.toggleEncryption(!contact.isEncrypted)
                        }
                    }) {
                        Image(systemName: contact.isEncrypted ? "lock.fill" : "lock.open.fill")
                    }
                    .alert(isPresented: $showingCannotEncryptAlert) {
                        Alert(title: Text("No OMEMO keys found"), message: Text("This contact may not support OMEMO encrypted messages. Please try again in a few seconds."), dismissButton: .default(Text("Close")))
                    }
                    .actionSheet(isPresented: $showingShouldDisableEncryptionAlert) {
                        ActionSheet(
                            title: Text("Disable encryption?"),
                            message: Text("Do you really want to disable encryption for this contact?"),
                            buttons: [
                                .cancel(
                                    Text("No, keep encryption activated"),
                                    action: { }
                                ),
                                .destructive(
                                    Text("Yes, deactivate encryption"),
                                    action: {
                                        showingCannotEncryptAlert = !contact.obj.toggleEncryption(!contact.isEncrypted)
                                    }
                                )
                            ]
                        )
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
#endif
                Spacer()
            }
                .foregroundColor(.primary)
            
            if(!contact.isGroup && (contact.statusMessage as String).count > 0) {
                Spacer()
                    .frame(height: 20)
                Text("Status message:")
                Text(contact.statusMessage as String)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            if(contact.isGroup && (contact.groupSubject as String).count > 0) {
                Spacer()
                    .frame(height: 20)
                if(contact.obj.mucType == "group") {
                    Text("Group subject:")
                } else {
                    Text("Channel subject:")
                }
                Text(contact.groupSubject as String)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ContactDetailsHeader_Previews: PreviewProvider {
    static var previews: some View {
        ContactDetailsHeader(contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(0)))
        ContactDetailsHeader(contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(1)))
        ContactDetailsHeader(contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(2)))
        ContactDetailsHeader(contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(3)))
        ContactDetailsHeader(contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(4)))
    }
}
