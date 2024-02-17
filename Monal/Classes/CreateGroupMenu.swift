//
//  AddContactMenu.swift
//  Monal
//
//  Created by Jan on 27.10.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

import MobileCoreServices
import UniformTypeIdentifiers
import SwiftUI
import monalxmpp
import OrderedCollections

struct CreateGroupMenu: View {
    @StateObject private var appDelegate: ObservableKVOWrapper<MonalAppDelegate>

    @State private var connectedAccounts: [xmpp]
    @State private var selectedAccount: xmpp?
    @State private var groupName: String = ""

    @State private var showAlert = false
    // note: dismissLabel is not accessed but defined at the .alert() section
    @State private var alertPrompt = AlertPrompt(dismissLabel: Text("Close"))
    @State private var selectedContacts : OrderedSet<MLContact> = []

    @ObservedObject private var overlay = LoadingOverlayState()
    
    private var delegate: SheetDismisserProtocol

    init(delegate: SheetDismisserProtocol) {
        _appDelegate = StateObject(wrappedValue: ObservableKVOWrapper(UIApplication.shared.delegate as! MonalAppDelegate))
        self.delegate = delegate

        let connectedAccounts = MLXMPPManager.sharedInstance().connectedXMPP as! [xmpp]
        self.connectedAccounts = connectedAccounts
        _selectedAccount = State(wrappedValue: connectedAccounts.first)
    }

    private func errorAlert(title: Text, message: Text = Text("")) {
        alertPrompt.title = title
        alertPrompt.message = message
        showAlert = true
    }

    var body: some View {
        Form {
            if(connectedAccounts.isEmpty) {
                Text("Please make sure at least one account has connected before trying to create new group.")
                    .foregroundColor(.secondary)
            }
            else
            {
                Section() {
                        Picker("Use account", selection: $selectedAccount) {
                            ForEach(Array(self.connectedAccounts.enumerated()), id: \.element) { idx, account in
                                Text(account.connectionProperties.identity.jid).tag(account)
                            }
                        }
                        .pickerStyle(.menu)
                    TextField(NSLocalizedString("Group Name (optional)", comment: "placeholder when creating new group"), text: $groupName)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                        .addClearButton(text:$groupName)

                    NavigationLink(destination: LazyClosureView(ContactPicker(account: self.selectedAccount!, selectedContacts: $selectedContacts)), label: {
                            Text("Change Group Members")
                        })
                    Button(action: {
                        showLoadingOverlay(overlay, headline: NSLocalizedString("Creating Group", comment: ""))
                        let roomJid = self.selectedAccount!.mucProcessor.createGroup(nil)
                        if(roomJid == nil) {
                            let groupContact = MLContact.createContact(fromJid: roomJid!, andAccountNo: self.selectedAccount!.accountNo)
                            hideLoadingOverlay(overlay)
                            self.delegate.dismissWithoutAnimation()
                            if let activeChats = self.appDelegate.obj.activeChats {
                                activeChats.presentChat(with:groupContact)
                            }
                        } else {
                            self.selectedAccount!.mucProcessor.addUIHandler({data in
                                let success : Bool = (data as! NSDictionary)["success"] as! Bool;
                                if(success) {
                                    self.selectedAccount!.mucProcessor.changeName(ofMuc: roomJid!, to: self.groupName)
                                    for user in self.selectedContacts {
                                        self.selectedAccount!.mucProcessor.setAffiliation("member", ofUser: user.contactJid, inMuc: roomJid!)
                                        self.selectedAccount!.mucProcessor.inviteUser(user.contactJid, inMuc: roomJid!)
                                    }
                                    let groupContact = MLContact.createContact(fromJid: roomJid!, andAccountNo: self.selectedAccount!.accountNo)
                                    hideLoadingOverlay(overlay)
                                    self.delegate.dismissWithoutAnimation()
                                    if let activeChats = self.appDelegate.obj.activeChats {
                                        activeChats.presentChat(with:groupContact)
                                    }
                                } else {
                                    hideLoadingOverlay(overlay)
                                    errorAlert(title: Text("Error creating group!"))
                                }
                            }, forMuc: roomJid!)
                        }
                    }, label: {
                        Text("Create new group")
                    })
                }
                if(self.selectedContacts.count > 0) {
                    Section(header: Text("Selected Group Members")) {
                        ForEach(self.selectedContacts, id: \.contactJid) { contact in
                            ContactEntry(contact: contact)
                        }
                        .onDelete(perform: { indexSet in
                            self.selectedContacts.remove(at: indexSet.first!)
                        })
                    }
                }
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton:.default(Text("Close"), action: {
                showAlert = false
            }))
        }
        .addLoadingOverlay(overlay)
        .navigationBarTitle("Create new group", displayMode: .inline)
        .navigationViewStyle(.stack)
    }
}

struct CreateGroupMenu_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        CreateGroupMenu(delegate: delegate)
    }
}
