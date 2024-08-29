//
//  AddContactMenu.swift
//  Monal
//
//  Created by Jan on 27.10.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

import OrderedCollections

struct CreateGroupMenu: View {
    private var appDelegate: MonalAppDelegate
    private var delegate: SheetDismisserProtocol
    @State private var connectedAccounts: [xmpp]
    @State private var selectedAccount: xmpp?
    @State private var groupName: String = ""
    @State private var showAlert = false
    // note: dismissLabel is not accessed but defined at the .alert() section
    @State private var alertPrompt = AlertPrompt(dismissLabel: Text("Close"))
    @State private var selectedContacts: OrderedSet<ObservableKVOWrapper<MLContact>> = []
    @State private var isEditingGroupName = false
    @StateObject private var overlay = LoadingOverlayState()

    init(delegate: SheetDismisserProtocol) {
        self.appDelegate = UIApplication.shared.delegate as! MonalAppDelegate
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

    // When a Form is placed inside a Popover, and the horizontal size class is regular, the spacing chosen by SwiftUI is incorrect.
    // In particular, the spacing between the top of the first element and the navigation bar is too small, meaning the two overlap.
    // This only happens when the view is inside a popover, and the horizontal size class is regular.
    // Therefore, it is inconvenient to apply some manual spacing, as this we would have to work out in which situations it should be applied.
    // Placing a Text view inside the header causes SwiftUI to add consistent spacing in all situations.
    var popoverFormSpacingWorkaround: some View {
        Text("")
    }

    var body: some View {
        Form {
            if connectedAccounts.isEmpty {
                Text("Please make sure at least one account has connected before trying to create new group.")
                    .foregroundColor(.secondary)
            }
            else
            {
                Section(header: popoverFormSpacingWorkaround) {
                    if connectedAccounts.count > 1 {
                        Picker(selection: $selectedAccount, label: Text("Use account")) {
                            ForEach(Array(self.connectedAccounts.enumerated()), id: \.element) { idx, account in
                                Text(account.connectionProperties.identity.jid).tag(account as xmpp?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    TextField(NSLocalizedString("Group Name (optional)", comment: "placeholder when creating new group"), text: $groupName, onEditingChanged: { isEditingGroupName = $0 })
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                        .addClearButton(isEditing: isEditingGroupName, text:$groupName)

                    Button(action: {
                        guard let generatedJid = self.selectedAccount!.mucProcessor.generateMucJid() else {
                            errorAlert(title: Text("Error creating group!"), message: Text("Your server does not provide a MUC component."))
                            return
                        }
                        showLoadingOverlay(overlay, headline: NSLocalizedString("Creating Group", comment: ""))
                        guard let roomJid = self.selectedAccount!.mucProcessor.createGroup(generatedJid) else {
                            //room already existing in our local bookmarks --> just open it
                            //this should never happen since we randomly generated a jid above
                            hideLoadingOverlay(overlay)
                            let groupContact = MLContact.createContact(fromJid: generatedJid, andAccountNo: self.selectedAccount!.accountNo)
                            self.delegate.dismissWithoutAnimation()
                            if let activeChats = self.appDelegate.activeChats {
                                activeChats.presentChat(with:groupContact)
                            }
                            return
                        }
                        self.selectedAccount!.mucProcessor.addUIHandler({_data in let data = _data as! NSDictionary
                            let success : Bool = data["success"] as! Bool;
                            if success {
                                DataLayer.sharedInstance().setFullName(self.groupName, forContact:roomJid, andAccount:self.selectedAccount!.accountNo)
                                self.selectedAccount!.mucProcessor.changeName(ofMuc: roomJid, to: self.groupName)
                                for user in self.selectedContacts {
                                    self.selectedAccount!.mucProcessor.setAffiliation("member", ofUser: user.contactJid, inMuc: roomJid)
                                    self.selectedAccount!.mucProcessor.inviteUser(user.contactJid, inMuc: roomJid)
                                }
                                let groupContact = MLContact.createContact(fromJid: roomJid, andAccountNo: self.selectedAccount!.accountNo)
                                hideLoadingOverlay(overlay)
                                self.delegate.dismissWithoutAnimation()
                                if let activeChats = self.appDelegate.activeChats {
                                    activeChats.presentChat(with:groupContact)
                                }
                            } else {
                                hideLoadingOverlay(overlay)
                                errorAlert(title: Text("Error creating group!"), message: Text(data["errorMessage"] as! String))
                            }
                        }, forMuc: roomJid)
                    }, label: {
                        Text("Create new group")
                    })
                }

                Section(header: Text("Selected Group Members")) {
                    NavigationLink(destination: LazyClosureView(ContactPicker(self.selectedAccount!, binding: $selectedContacts))) {
                        Text("Change Group Members")
                    }
                    ForEach(self.selectedContacts, id: \.obj.contactJid) { contact in
                        ContactEntry(contact: contact)
                    }
                    .onDelete(perform: { indexSet in
                        self.selectedContacts.remove(at: indexSet.first!)
                    })
                }
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton:.default(Text("Close"), action: {
                showAlert = false
            }))
        }
        .addLoadingOverlay(overlay)
        .navigationBarTitle(Text("Create new group"), displayMode: .inline)
    }
}

struct CreateGroupMenu_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        CreateGroupMenu(delegate: delegate)
    }
}
