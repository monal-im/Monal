//
//  LoginCredentials.swift
//  Monal
//
//  Created by lissine on 2/11/2024.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import SAMKeychain

struct LoginCredentials: View {
    @Environment(\.presentationMode) var presentationMode
    let accountID: NSNumber?
    let jid: String
    let resource: String
    @State private var password: String
    @State private var hardcodedServer: String
    @State private var hardcodedPort: String
    @State private var allowPlainAuth: Bool
    @State private var forceDirectTLS: Bool

    init(accountID: NSNumber?) {
        self.accountID = accountID
        guard accountID != nil,
                let settings = DataLayer.sharedInstance().details(forAccount: accountID!) else {
            self.jid = ""
            self.resource = ""
            self.hardcodedServer = ""
            self.hardcodedPort = "5222"
            self.allowPlainAuth = false
            self.forceDirectTLS = false
            self.password = ""
            return
        }

        self.jid = "\(settings["username"]!)@\(settings["domain"]!)"
        self.resource = settings["resource"] as? String ?? ""
        _hardcodedServer = State(initialValue: settings["server"] as? String ?? "")
        _hardcodedPort = State(initialValue: "\(settings["other_port"] ?? 5222)")
        _allowPlainAuth = State(initialValue: settings["plain_activated"] as? Bool ?? false)
        _forceDirectTLS = State(initialValue: settings["directTLS"] as? Bool ?? false)
        _password = State(initialValue: SAMKeychain.password(forService: kMonalKeychainName, account: self.accountID!.stringValue) ?? "")
    }

    var body: some View {
        Form {
            Section(header: Text("")) {
                HStack {
                    Text("XMPP ID")
                    Spacer()
                    Text(self.jid)
                }
                HStack {
                    Text("Password")
                    Spacer()
#if IS_QUICKSY
                    TextField("Password", text: $password)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
#else
                    SecureField("Password", text: $password)
#endif
                }
            }

            Section(header: Text("Advanced")) {
                HStack {
                    Text("Server")
                    Spacer()
                    TextField("Optional Hardcoded Hostname", text: $hardcodedServer)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }

                if !hardcodedServer.isEmpty {
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("Optional Hardcoded Port", text: $hardcodedPort)
                            .keyboardType(.numberPad)
                            .onDisappear {
                                hardcodedPort = "5222"
                            }
                    }

                    Toggle(isOn: $forceDirectTLS) {
                        Text("Always use direct TLS, not STARTTLS")
                    }
                    .multilineTextAlignment(.leading)
                    .onDisappear {
                        forceDirectTLS = false
                    }
                }

                Toggle(isOn: $allowPlainAuth) {
                    Text("Allow MITM-prone PLAIN authentication")
                }
                // The plain auth setting is read only, to prevent downgrades. TODO: allow upgrading this setting using the SCRAM preload list
                .disabled(true)
                .multilineTextAlignment(.leading)

                HStack {
                    Text("Resource")
                    Spacer()
                    Text(self.resource)
                }
            }

        }
        .multilineTextAlignment(.trailing)
        .navigationTitle("Login Credetials")
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abort") {
                    self.presentationMode.wrappedValue.dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    guard accountID != nil else {
                        self.presentationMode.wrappedValue.dismiss()
                        return
                    }

                    var settings = DataLayer.sharedInstance().details(forAccount: accountID!) as! [String: Any]
                    settings["plain_activated"] = self.allowPlainAuth
                    settings["directTLS"] = self.forceDirectTLS
                    settings["server"] = self.hardcodedServer
                    settings["other_port"] = self.hardcodedPort
                    // Save the updated settings in the DB
                    DataLayer.sharedInstance().updateAccoun(with: settings)
                    // Save the password in the Keychain
                    if !self.password.isEmpty {
                        MLXMPPManager.sharedInstance().updatePassword(self.password, forAccount: self.accountID!)
                    }
                    self.presentationMode.wrappedValue.dismiss()

                    // Disconnect and reconnect so the new credentials / settings take effect
                    MLXMPPManager.sharedInstance().disconnectAccount(self.accountID!, withExplicitLogout: true)
                    MLXMPPManager.sharedInstance().connectAccount(self.accountID!)
                }
                // the jid can be empty if this view was somehow accessed while accountID is nil
                .disabled(password.isEmpty || jid.isEmpty)
            }
        }
    }
}
