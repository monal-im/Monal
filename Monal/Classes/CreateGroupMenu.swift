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

struct CreateGroupMenu: View {
    var delegate: SheetDismisserProtocol

    @State private var connectedAccounts: [xmpp]
    @State private var selectedAccount: Int
    @State private var groupName: String = ""

    @State private var showAlert = false
    // note: dismissLabel is not accessed but defined at the .alert() section
    @State private var alertPrompt = AlertPrompt(dismissLabel: Text("Close"))
    @State private var selectedContacts : [MLContact] = []

    @ObservedObject private var overlay = LoadingOverlayState()

    @State private var showQRCodeScanner = false
    @State private var success = false

    private let dismissWithNewGroup: (MLContact) -> ()

    init(delegate: SheetDismisserProtocol, dismissWithNewGroup: @escaping (MLContact) -> (), prefillJid: String = "", preauthToken:String? = nil) {
        // FIXME
        self.delegate = delegate
        self.dismissWithNewGroup = dismissWithNewGroup
        self.groupName = prefillJid
        // self.preauthToken = preauthToken

        let connectedAccounts = MLXMPPManager.sharedInstance().connectedXMPP as! [xmpp]
        self.connectedAccounts = connectedAccounts
        self.selectedAccount = connectedAccounts.first != nil ? 0 : -1;
    }

    // FIXME duplicate code from WelcomeLogIn.swift, maybe move to SwiftuiHelpers

    private func errorAlert(title: Text, message: Text = Text("")) {
        alertPrompt.title = title
        alertPrompt.message = message
        showAlert = true
    }

    private func successAlert(title: Text, message: Text) {
        alertPrompt.title = title
        alertPrompt.message = message
        self.success = true // < dismiss entire view on close
        showAlert = true
    }

    private var buttonColor: Color {
        return Color(UIColor.systemBlue)
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
                    if(connectedAccounts.count > 1) {
                        Picker("Use account", selection: $selectedAccount) {
                            ForEach(Array(self.connectedAccounts.enumerated()), id: \.element) { idx, account in
                                Text(account.connectionProperties.identity.jid).tag(idx)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    TextField("Group Name (optional)", text: $groupName)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                        .addClearButton(text:$groupName)

                    NavigationLink(destination: LazyClosureView(ContactPicker(excludedContacts: [], selectedContacts: self.selectedContacts, selectedContactsCallback: { selectedContacts in
                        self.selectedContacts = selectedContacts
                    })), label: {
                            Text("Group Members")
                        })
                }
                if(self.selectedContacts.count > 0) {
                    Section(header: Text("Selected Group Members")) {
                        ForEach(self.selectedContacts, id: \.self) { contact in
                            ContactEntry(contact: contact)
                        }
                    }
                    Section {
                        Button(action: {
                            
                        }, label: {
                            Text("Create new group")
                        })
                    }
                }
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton:.default(Text("Close"), action: {
                showAlert = false
                if self.success == true {
                    // TODO dismissWithNewGroup
                }
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
        CreateGroupMenu(delegate: delegate, dismissWithNewGroup: { c in
        })
    }
}
