//
//  AddContactMenu.swift
//  Monal
//
//  Created by Jan on 27.10.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

import SwiftUI
import monalxmpp

struct AddContactMenu: View {
    var delegate: SheetDismisserProtocol
    static private let jidFaultyPattern = "^.+\\..{2,}$"

    @State private var connectedAccounts: [xmpp]
    @State private var selectedAccount: Int
    @State private var scannedFingerprints: Dictionary<Int, String>? = nil
    @State private var importScannedFingerprints: Bool = false
    @State private var toAdd: String = ""

    @State private var showAlert = false
    @State private var alertPrompt = AlertPrompt(dismissLabel: Text("Close")) // note: dismissLabel is not accessed but defined at the .alert() section

    @ObservedObject private var overlay = LoadingOverlayState()

    @State private var showQRCodeScanner = false
    @State private var success = false

    // FIXME duplicate code from WelcomeLogIn.swift, maybe move to SwiftuiHelpers
    private var toAddEmptyAlert: Bool {
        alertPrompt.title = Text("No Empty Values!")
        alertPrompt.message = Text("Please make sure you have entered a valid jid.")
        return toAddEmpty
    }

    private var toAddInvalidAlert: Bool {
        alertPrompt.title = Text("Invalid Credentials!")
        alertPrompt.message = Text("The jid you want to add should be in in the format user@domain.tld.")
        return toAddInvalid
    }
    
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
    
    private var toAddEmpty: Bool {
        return toAdd.isEmpty
    }
    
    private var toAddInvalid: Bool {
        return toAdd.range(of: AddContactMenu.jidFaultyPattern, options:.regularExpression) == nil
    }

    private var buttonColor: Color {
        return toAddEmpty || toAddInvalid ? Color(UIColor.systemGray) : Color(UIColor.systemBlue)
    }

    func addJid(jid: String) {
        showLoadingOverlay(overlay, headline: NSLocalizedString("Adding...", comment: ""))
        let account = self.connectedAccounts[selectedAccount]
        account.checkJidType(jid, withCompletion: { type, errorMsg in
            if(type == "account") {
                hideLoadingOverlay(overlay)
                let contact = MLContact.createContact(fromJid: jid, andAccountNo: account.accountNo)
                MLXMPPManager.sharedInstance().add(contact)
                successAlert(title: Text("Permission Requested"), message: Text("The new contact will be added to your contacts list when the person you've added has approved your request."))
            } else if(type == "muc") {
                showLoadingOverlay(overlay, headline: NSLocalizedString("Adding MUC...", comment: ""))
                let accountNo = account.accountNo;
                account.mucProcessor.addUIHandler({data in
                    let success : Bool = (data as! NSDictionary)["success"] as! Bool;
                    hideLoadingOverlay(overlay)
                    if(success) {
                        MLContact.createContact(fromJid: jid, andAccountNo: accountNo) // FIXME Actually do something with it
                        successAlert(title: Text("Success!"), message: Text(String.localizedStringWithFormat("Successfully joined MUC %s!", jid)))
                    } else {
                        errorAlert(title: Text("Error entering group chat"))
                    }
                }, forMuc: jid)
                account.joinMuc(jid)
            } else {
                hideLoadingOverlay(overlay)
                errorAlert(title: Text("Error"), message: Text(errorMsg ?? "Undefined error"))
            }
        })
    }

    var body: some View {
        NavigationView {
            Form {
                if(connectedAccounts.isEmpty) {
                    Text("Please make sure at least one account has connected before trying to add a contact or channel.")
                        .foregroundColor(.secondary)
                }
                else
                {
                    Section(header: Text(verbatim: "Contact and Channel Jids are usually in the format: name@domain.tld")) {
                        if(connectedAccounts.count > 1) {
                            Picker("Use account", selection: $selectedAccount) {
                                ForEach(Array(self.connectedAccounts.enumerated()), id: \.element) { idx, account in
                                    Text(account.connectionProperties.identity.jid).tag(idx)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        TextField("Contact or Channel Jid", text: $toAdd)
                            .autocorrectionDisabled()
                            .autocapitalization(.none)
                            .disabled(scannedFingerprints != nil)
                            .foregroundColor(scannedFingerprints != nil ? .secondary : .primary)
                    }
                    if(scannedFingerprints != nil && scannedFingerprints!.count > 1) {
                        Section(header: Text("A contact was scanned through the QR code scanner")) {
                            Toggle(isOn: $importScannedFingerprints, label: {
                                Text("Import and trust OMEMO fingerprints from QR code")
                            })
                        }
                    }
                    Section {
                        if(scannedFingerprints != nil) {
                            Button(action: {
                                toAdd = ""
                                importScannedFingerprints = true
                                scannedFingerprints = nil
                            }, label: {
                                Text("Clear scanned contact")
                                    .foregroundColor(.red)
                            })
                        }
                        Button(action: {
                            showAlert = toAddEmptyAlert || toAddInvalidAlert

                            if(!showAlert) {
                                let jidComponents = HelperTools.splitJid(toAdd)
                                if(jidComponents["node"] == nil || jidComponents["host"] == nil || jidComponents["node"]!.isEmpty || jidComponents["host"]!.isEmpty) {
                                    errorAlert(title: Text("Error"), message: Text("Something went wrong while parsing the string..."))
                                    showAlert = true
                                    return
                                }
                                // use the canonized jid from now on (lowercased, resource removed etc.)
                                addJid(jid: jidComponents["user"]!) // check if user entry exists in components?
                            }
                        }, label: {
                            scannedFingerprints == nil ? Text("Add Channel or Contact") : Text("Add scanned Channel or Contact")
                        })
                        .foregroundColor(buttonColor)
                        .alert(isPresented: $showAlert) {
                            Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton:.default(Text("Close"), action: {
                                showAlert = false
                                if(self.success == true) {
                                    self.delegate.dismiss()
                                }
                            }))
                        }
                    }
                }
            }
        }
        .navigationBarTitle("Add Contact or Channel", displayMode: .inline)
        .navigationViewStyle(.stack)
        .toolbar(content: {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    self.showQRCodeScanner = true
                }, label: {
                    Image(systemName: "camera.fill").foregroundColor(monalGreen)
                })
            }
        })
        .sheet(isPresented: $showQRCodeScanner) {
            NavigationView {
                MLQRCodeScanner(
                    handleContact: { jid, fingerprints in
                        self.toAdd = jid
                        showQRCodeScanner = false
                        self.scannedFingerprints = fingerprints
                        self.importScannedFingerprints = true
                    }, handleClose: {
                        self.showQRCodeScanner = false
                    }
                )
                .navigationTitle("QR-Code Scanner")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(content: {
                    ToolbarItem(placement: .navigationBarLeading, content: {
                        Button(action: {
                            self.showQRCodeScanner = false
                        }, label: {
                            Text("Close")
                        })
                        .foregroundColor(monalGreen)
                    })
                })
            }
        }
    }

    init(delegate: SheetDismisserProtocol) {
        self.delegate = delegate
        let connectedAccounts = MLXMPPManager.sharedInstance().connectedXMPP as! [xmpp]
        self.connectedAccounts = connectedAccounts
        self.selectedAccount = connectedAccounts.first != nil ? 0 : -1;
    }
}

struct AddContactMenu_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        AddContactMenu(delegate: delegate)
    }
}
