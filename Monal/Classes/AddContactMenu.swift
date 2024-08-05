//
//  AddContactMenu.swift
//  Monal
//
//  Created by Jan on 27.10.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

import MobileCoreServices
import UniformTypeIdentifiers

struct AddContactMenu: View {
    var delegate: SheetDismisserProtocol
    static private let jidFaultyPattern = "^([^@]+@)?.+(\\..{2,})?$"

    @State private var connectedAccounts: [xmpp]
    @State private var selectedAccount: Int
    @State private var scannedFingerprints: [NSNumber:Data]? = nil
    @State private var importScannedFingerprints: Bool = false
    @State private var toAdd: String = ""

    @State private var showInvitationError = false
    @State private var showAlert = false
    // note: dismissLabel is not accessed but defined at the .alert() section
    @State private var alertPrompt = AlertPrompt(dismissLabel: Text("Close"))
    @State private var invitationResult: [String:AnyObject]? = nil

    @StateObject private var overlay = LoadingOverlayState()

    @State private var showQRCodeScanner = false
    @State private var success = false
    @State private var newContact : MLContact?

    @State private var isEditingJid = false

    private let dismissWithNewContact: (MLContact) -> ()
    private let preauthToken: String?

    init(delegate: SheetDismisserProtocol, dismissWithNewContact: @escaping (MLContact) -> (), prefillJid: String = "", preauthToken:String? = nil, prefillAccount:xmpp? = nil, omemoFingerprints: [NSNumber:Data]? = nil) {
        self.delegate = delegate
        self.dismissWithNewContact = dismissWithNewContact
        //self.toAdd = State(wrappedValue: prefillJid)
        self.toAdd = prefillJid
        self.preauthToken = preauthToken
        //only display omemo ui part if there are any fingerprints (the checks below test for nil, not for 0)
        if omemoFingerprints?.count ?? 0 > 0 {
            self.scannedFingerprints = omemoFingerprints
        }
        
        let connectedAccounts = MLXMPPManager.sharedInstance().connectedXMPP as! [xmpp]
        self.connectedAccounts = connectedAccounts
        self.selectedAccount = connectedAccounts.first != nil ? 0 : -1;
        if let prefillAccount = prefillAccount {
            for index in connectedAccounts.indices {
                if connectedAccounts[index].accountNo.isEqual(to:prefillAccount.accountNo) {
                    self.selectedAccount = index
                }
            }
        }
    }
    
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

    func trustFingerprints(_ fingerprints:[NSNumber:Data]?, for jid:String, on account:xmpp) {
        //we don't untrust other devices not included in here, because conversations only exports its own fingerprint
        if let fingerprints = fingerprints {
            for (deviceId, fingerprint) in fingerprints {
                let address = SignalAddress.init(name:jid, deviceId:deviceId.int32Value)
                let knownDevices = Array(account.omemo.knownDevices(forAddressName:jid))
                if !knownDevices.contains(deviceId) {
                    account.omemo.addIdentityManually(address, identityKey:fingerprint)
                    assert(account.omemo.getIdentityFor(address) == fingerprint, "The stored and created fingerprint should match")
                }
                //trust device/fingerprint if fingerprints match
                let knownFingerprintHex = HelperTools.signalHexKey(with:account.omemo.getIdentityFor(address))
                let addedFingerprintHex = HelperTools.signalHexKey(with:fingerprint)
                if knownFingerprintHex.uppercased() == addedFingerprintHex.uppercased() {
                    account.omemo.updateTrust(true, for:address)
                }
            }
        }
    }
    
    func addJid(jid: String) {
        let account = self.connectedAccounts[selectedAccount]
        let contact = MLContact.createContact(fromJid: jid, andAccountNo: account.accountNo)
        if contact.isInRoster {
            self.newContact = contact
            //import omemo fingerprints as manually trusted, if requested
            trustFingerprints(self.importScannedFingerprints ? self.scannedFingerprints : [:], for:jid, on:account)
            //only alert of already known contact if we did not import the omemo fingerprints
            if !self.importScannedFingerprints || self.scannedFingerprints?.count ?? 0 == 0 {
                if self.connectedAccounts.count > 1 {
                    self.success = true
                    successAlert(title: Text("Already present"), message: Text("This contact is already in the contact list of the selected account"))
                } else {
                    self.success = true
                    successAlert(title: Text("Already present"), message: Text("This contact is already in your contact list"))
                }
            }
            return
        }
        showPromisingLoadingOverlay(overlay, headline:NSLocalizedString("Adding...", comment: ""), description:"") {
            account.checkJidType(jid)
        }.done { type in
            let type = type as! String
            if type == "account" {
                let contact = MLContact.createContact(fromJid: jid, andAccountNo: account.accountNo)
                self.newContact = contact
                MLXMPPManager.sharedInstance().add(contact, withPreauthToken:preauthToken)
                //import omemo fingerprints as manually trusted, if requested
                trustFingerprints(self.importScannedFingerprints ? self.scannedFingerprints : [:], for:jid, on:account)
                successAlert(title: Text("Permission Requested"), message: Text("The new contact will be added to your contacts list when the person you've added has approved your request."))
            } else if type == "muc" {
                showPromisingLoadingOverlay(overlay, headlineView:Text("Adding Group/Channel..."), descriptionView:Text("")) {
                    promisifyMucAction(account:account, mucJid:jid) {
                        account.joinMuc(jid)
                    }
                }.done { _ in
                    self.newContact = MLContact.createContact(fromJid: jid, andAccountNo: account.accountNo)
                    successAlert(title: Text("Success!"), message: Text("Successfully joined group/channel \(jid)!"))
                }.catch { error in
                    errorAlert(title: Text("Error entering group/channel!"), message: Text("\(String(describing:error))"))
                }
            }
        }.catch { error in
            errorAlert(title: Text("Error"), message: Text(error.localizedDescription))
        }
    }

    var body: some View {
        let account = self.connectedAccounts[selectedAccount]
        let splitJid = HelperTools.splitJid(account.connectionProperties.identity.jid)
        Form {
            if connectedAccounts.isEmpty {
                Text("Please make sure at least one account has connected before trying to add a contact or channel.")
                    .foregroundColor(.secondary)
            }
            else
            {
                if DataLayer.sharedInstance().allContactRequests().count > 0 {
                    ContactRequestsMenu()
                }
                
                Section(header:Text("Contact and Group/Channel Jids are usually in the format: name@domain.tld")) {
                    if connectedAccounts.count > 1 {
                        Picker("Use account", selection: $selectedAccount) {
                            ForEach(Array(self.connectedAccounts.enumerated()), id: \.element) { idx, account in
                                Text(account.connectionProperties.identity.jid).tag(idx)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    TextField(NSLocalizedString("Contact-, Group- or Channel-Jid", comment: "placeholder when adding jid"), text: $toAdd, onEditingChanged: { isEditingJid = $0 })
                        .textInputAutocapitalization(.never)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .addClearButton(isEditing: isEditingJid, text:$toAdd)
                        .disabled(scannedFingerprints != nil)
                        .foregroundColor(scannedFingerprints != nil ? .secondary : .primary)
                        .onChange(of: toAdd) { _ in toAdd = toAdd.replacingOccurrences(of: " ", with: "") }
                    
                    if scannedFingerprints != nil && scannedFingerprints!.count > 0 {
                        Section(header: Text("A contact was scanned through the QR code scanner")) {
                            Toggle(isOn: $importScannedFingerprints) {
                                Text("Import and trust OMEMO fingerprints from QR code")
                            }
                        }
                    }
                    
                    if scannedFingerprints != nil {
                        Button(action: {
                            toAdd = ""
                            importScannedFingerprints = true
                            scannedFingerprints = nil
                        }, label: {
                            Text("Clear scanned contact")
                                .foregroundColor(.red)
                        })
                    }
                    
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            showAlert = toAddEmptyAlert || toAddInvalidAlert

                            if !showAlert {
                                let jidComponents = HelperTools.splitJid(toAdd)
                                if jidComponents["host"] == nil || jidComponents["host"]!.isEmpty {
                                    errorAlert(title: Text("Error"), message: Text("Something went wrong while parsing your input..."))
                                    showAlert = true
                                    return
                                }
                                // use the canonized jid from now on (lowercased, resource removed etc.)
                                addJid(jid: jidComponents["user"]!)
                            }
                        }) {
                            scannedFingerprints == nil ? Text("Add") : Text("Add scanned contact")
                        }
                        //.fontWeight(.bold)
                        .padding(10)
                        .background(toAddEmpty || toAddInvalid ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .disabled(toAddEmpty || toAddInvalid)
                    }
                }
                
                if DataLayer.sharedInstance().allContactRequests().count == 0 {
                    Section {
                        ContactRequestsMenu()
                    }
                }
            }
        }
        .padding()
        .alert(isPresented: $showAlert) {
            Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton:.default(Text("Close"), action: {
                showAlert = false
                if self.success == true {
                    if self.newContact != nil {
                        self.dismissWithNewContact(newContact!)
                    } else {
                        self.delegate.dismiss()
                    }
                }
            }))
        }
        .richAlert(isPresented: $invitationResult, title:Text("Invitation for \(splitJid["host"]!) created")) { data in
            VStack {
                Image(uiImage: createQrCode(value: data["landing"] as! String))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .aspectRatio(1, contentMode: .fit)

                if let expires = data["expires"] as? Date {
                    Text("This invitation will expire on \(expires.formatted(date:.numeric, time:.shortened))")
                    .font(.footnote)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } buttons: { data in 
            Button(action: {
                UIPasteboard.general.setValue(data["landing"] as! String, forPasteboardType:UTType.utf8PlainText.identifier as String)
                invitationResult = nil
            }) {
                ShareLink("Share invitation link", item: URL(string: data["landing"] as! String)!)
            }
            Button(action: {
                invitationResult = nil
            }) {
                Text("Close")
                    .frame(maxWidth: .infinity)
            }
        }
        .addLoadingOverlay(overlay)
        .navigationBarTitle(Text("Add Contact or Channel"), displayMode: .inline)
        .navigationViewStyle(.stack)
        .toolbar(content: {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if account.connectionProperties.discoveredAdhocCommands["urn:xmpp:invite#invite"] != nil {
                    Button(action: {
                        DDLogVerbose("Trying to create invitation for: \(String(describing:splitJid["host"]!))")
                        showLoadingOverlay(overlay, headline: NSLocalizedString("Creating invitation...", comment: ""))
                        account.createInvitation(completion: {
                            let result = $0 as! [String:AnyObject]
                            DispatchQueue.main.async {
                                hideLoadingOverlay(overlay)
                                DDLogVerbose("Got invitation result: \(String(describing:result))")
                                if result["success"] as! Bool == true {
                                    invitationResult = result
                                } else {
                                    errorAlert(title:Text("Failed to create invitation for \(splitJid["host"]!)"), message:Text(result["error"] as! String))
                                }
                            }
                        })
                    }, label: {
                        Image(systemName: "square.and.arrow.up").foregroundColor(monalGreen)
                    })
                }
                Button(action: {
                    self.showQRCodeScanner = true
                }, label: {
                    Image(systemName: "camera.fill").foregroundColor(monalGreen)
                })
            }
        })
        .sheet(isPresented: $showQRCodeScanner) {
            NavigationView {
                MLQRCodeScanner(handleClose: {
                    self.showQRCodeScanner = false
                })
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
}

struct AddContactMenu_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        AddContactMenu(delegate: delegate, dismissWithNewContact: { c in
        })
    }
}
