//
//  WelcomeLogIn.swift
//  Monal
//
//  Created by CC on 22.04.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import SwiftUI
import monalxmpp

struct WelcomeLogIn: View {
    static private let credFaultyPattern = "^.+@.+\\..{2,}$"
    
    var delegate: SheetDismisserProtocol
    
    @State private var isEditingJid: Bool = false
    @State private var jid: String = ""
    @State private var isEditingPassword: Bool = false
    @State private var password: String = ""

    @State private var showAlert = false
    @State private var showQRCodeScanner = false

    // login related
    @State private var currentTimeout : DispatchTime? = nil
    @State private var errorObserverEnabled = false
    @State private var newAccountNo: NSNumber? = nil
    @State private var loginComplete = false
    @State private var isLoadingOmemoBundles = false
    
    @State private var alertPrompt = AlertPrompt(dismissLabel: Text("Close"))
    @StateObject private var overlay = LoadingOverlayState()

#if IS_ALPHA
    let appLogoId = "AlphaAppLogo"
#elseif IS_QUICKSY
    let appLogoId = "QuicksyAppLogo"
#else
    let appLogoId = "AppLogo"
#endif
    
    private var credentialsEnteredAlert: Bool {
        alertPrompt.title = Text("Empty Values!")
        alertPrompt.message = Text("Please make sure you have entered both a username and password.")
        return credentialsEntered
    }

    private var credentialsFaultyAlert: Bool {
        alertPrompt.title = Text("Invalid Credentials!")
        alertPrompt.message = Text("Your XMPP jid should be in in the format user@domain.tld. For special configurations, use manual setup.")
        return credentialsFaulty
    }

    private var credentialsExistAlert: Bool {
        alertPrompt.title = Text("Duplicate jid!")
        alertPrompt.message = Text("This account already exists in Monal.")
        return credentialsExist
    }

    private func showTimeoutAlert() {
        DDLogVerbose("Showing timeout alert...")
        hideLoadingOverlay(overlay)
        alertPrompt.title = Text("Timeout Error")
        alertPrompt.message = Text("We were not able to connect your account. Please check your username and password and make sure you are connected to the internet.")
        showAlert = true
    }

    private func showSuccessAlert() {
        hideLoadingOverlay(overlay)
        alertPrompt.title = Text("Success!")
        alertPrompt.message = Text("You are set up and connected.")
        showAlert = true
    }

    private func showLoginErrorAlert(errorMessage: String) {
        hideLoadingOverlay(overlay)
        alertPrompt.title = Text("Error")
        alertPrompt.message = Text(String(format: NSLocalizedString("We were not able to connect your account. Please check your username and password and make sure you are connected to the internet.\n\nTechnical error message: %@", comment: ""), errorMessage))
        showAlert = true
    }

    private var credentialsEntered: Bool {
        return !jid.isEmpty && !password.isEmpty
    }
    
    private var credentialsFaulty: Bool {
        return jid.range(of: WelcomeLogIn.credFaultyPattern, options:.regularExpression) == nil
    }
    
    private var credentialsExist: Bool {
        let components = jid.components(separatedBy: "@")
        return DataLayer.sharedInstance().doesAccountExistUser(components[0], andDomain:components[1])
    }

    private var buttonColor: Color {
        return !credentialsEntered || credentialsFaulty ? Color(UIColor.systemGray) : Color(UIColor.systemBlue)
    }
    
    private func startLoginTimeout() {
        let newTimeout = DispatchTime.now() + 30.0;
        self.currentTimeout = newTimeout
        DispatchQueue.main.asyncAfter(deadline: newTimeout) {
            if(newTimeout == self.currentTimeout) {
                DDLogWarn("First login timeout triggered...")
                if(self.newAccountNo != nil) {
                    DDLogVerbose("Removing account...")
                    MLXMPPManager.sharedInstance().removeAccount(forAccountNo: self.newAccountNo!)
                    self.newAccountNo = nil
                }
                self.currentTimeout = nil
                showTimeoutAlert()
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                HStack () {
                    Image(decorative: appLogoId)
                        .resizable()
                        .frame(width: CGFloat(120), height: CGFloat(120), alignment: .center)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding()
                    
                    Text("Log in to your existing account or register a new account. If required you will find more advanced options in Monal settings.")
                        .padding()
                        .padding(.leading, -16.0)
                    
                }
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.systemBackground))

                Form {
                    Text("I already have an account:")
                    //for ios >= 15.0
                    //.listRowSeparator(.hidden)
                    
                    TextField(NSLocalizedString("user@domain.tld", comment: "placeholder when adding account"), text: Binding(
                        get: { self.jid },
                        set: { string in self.jid = string.lowercased().replacingOccurrences(of: " ", with: "") }), onEditingChanged: { isEditingJid = $0 }
                    )
                    //ios15: .textInputAutocapitalization(.never)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .addClearButton(isEditing: isEditingJid, text: $jid)
                    
                    SecureField(NSLocalizedString("Password", comment: "placeholder when adding account"), text: $password)
                        .addClearButton(isEditing:  password.count > 0
                                        , text: $password)
                    
                    HStack() {
                        Button(action: {
                            showAlert = !credentialsEnteredAlert || credentialsFaultyAlert || credentialsExistAlert

                            if (!showAlert) {
                                startLoginTimeout()
                                showLoadingOverlay(overlay, headline:NSLocalizedString("Logging in", comment: ""))
                                self.errorObserverEnabled = true
                                self.newAccountNo = MLXMPPManager.sharedInstance().login(self.jid, password: self.password)
                                if(self.newAccountNo == nil) {
                                    currentTimeout = nil // <- disable timeout on error
                                    errorObserverEnabled = false
                                    showLoginErrorAlert(errorMessage:NSLocalizedString("Account already configured in Monal!", comment: ""))
                                    self.newAccountNo = nil
                                }
                            }
                        }){
                            Text("Login")
                                .frame(maxWidth: .infinity)
                                .padding(9.0)
                                .background(Color(UIColor.tertiarySystemFill))
                                .foregroundColor(buttonColor)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .alert(isPresented: $showAlert) {
                            Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton: .default(alertPrompt.dismissLabel, action: {
                                if(self.loginComplete == true) {
                                    self.delegate.dismiss()
                                }
                            }))
                        }

                        // Just sets the credential in jid and password variables and shows them in the input fields
                        // so user can control what they scanned and if o.k. login via the "Login" button.
                        Button(action: {
                            showQRCodeScanner = true
                        }){
                            Image(systemName: "qrcode")
                                .frame(maxHeight: .infinity)
                                .padding(9.0)
                                .background(Color(UIColor.tertiarySystemFill))
                                .foregroundColor(.black)
                                .clipShape(Circle())
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        .sheet(isPresented: $showQRCodeScanner) {
                            Text("QR-Code Scanner").font(.largeTitle.weight(.bold))
                            // Get existing credentials from QR and put values in jid and password
                            MLQRCodeScanner(
                                handleLogin: { jid, password in
                                    self.jid = jid
                                    self.password = password
                                }, handleClose: {
                                    self.showQRCodeScanner = false
                                }
                            )
                        }
                    }
                    
                    NavigationLink(destination: LazyClosureView(RegisterAccount(delegate: self.delegate))) {
                        Text("Register a new account")
                        .foregroundColor(monalDarkGreen)
                    }
                    
                    if(DataLayer.sharedInstance().enabledAccountCnts() == 0) {
                        Button(action: {
                            self.delegate.dismiss()
                        }){
                            Text("Set up account later")
                                .frame(maxWidth: .infinity)
                                .padding(.top, 10.0)
                                .padding(.bottom, 9.0)
                                .foregroundColor(Color(UIColor.systemGray))
                        }
                    }
                }
                .frame(minHeight: 310)
                .textFieldStyle(.roundedBorder)
                .onAppear {UITableView.appearance().tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 30))}
            }
        }
        .addLoadingOverlay(overlay)
        .navigationBarTitle(Text("Welcome"))
        .onDisappear {UITableView.appearance().tableHeaderView = nil}       //why that??
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kXMPPError")).receive(on: RunLoop.main)) { notification in
            if(self.errorObserverEnabled == false) {
                return
            }
            if let xmppAccount = notification.object as? xmpp, let newAccountNo : NSNumber = self.newAccountNo, let errorMessage = notification.userInfo?["message"] as? String {
                if(xmppAccount.accountNo.intValue == newAccountNo.intValue) {
                    DispatchQueue.main.async {
                        currentTimeout = nil // <- disable timeout on error
                        errorObserverEnabled = false
                        showLoginErrorAlert(errorMessage: errorMessage)
                        MLXMPPManager.sharedInstance().removeAccount(forAccountNo: newAccountNo)
                        self.newAccountNo = nil
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMLResourceBoundNotice")).receive(on: RunLoop.main)) { notification in
            if let xmppAccount = notification.object as? xmpp, let newAccountNo : NSNumber = self.newAccountNo {
                if(xmppAccount.accountNo.intValue == newAccountNo.intValue) {
                    DispatchQueue.main.async {
                        currentTimeout = nil // <- disable timeout on successful connection
                        self.errorObserverEnabled = false
                        showLoadingOverlay(overlay, headline:NSLocalizedString("Loading contact list", comment: ""))
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalUpdateBundleFetchStatus")).receive(on: RunLoop.main)) { notification in
            if let notificationAccountNo = notification.userInfo?["accountNo"] as? NSNumber, let completed = notification.userInfo?["completed"] as? NSNumber, let all = notification.userInfo?["all"] as? NSNumber, let newAccountNo : NSNumber = self.newAccountNo {
                if(notificationAccountNo.intValue == newAccountNo.intValue) {
                    isLoadingOmemoBundles = true
                    DispatchQueue.main.async {
                        showLoadingOverlay(
                            overlay, 
                            headline:NSLocalizedString("Loading omemo bundles", comment: ""),
                            description:String(format: NSLocalizedString("Loading omemo bundles: %@ / %@", comment: ""), completed, all)
                        )
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalFinishedOmemoBundleFetch")).receive(on: RunLoop.main)) { notification in
            if let notificationAccountNo = notification.userInfo?["accountNo"] as? NSNumber, let newAccountNo : NSNumber = self.newAccountNo {
                if(notificationAccountNo.intValue == newAccountNo.intValue && isLoadingOmemoBundles) {
                    DispatchQueue.main.async {
                        self.loginComplete = true
                        showSuccessAlert()
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalFinishedCatchup")).receive(on: RunLoop.main)) { notification in
            if let xmppAccount = notification.object as? xmpp, let newAccountNo : NSNumber = self.newAccountNo {
                if(xmppAccount.accountNo.intValue == newAccountNo.intValue && !isLoadingOmemoBundles) {
                    DispatchQueue.main.async {
                        self.loginComplete = true
                        showSuccessAlert()
                    }
                }
            }
        }
    }
}

struct WelcomeLogIn_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        WelcomeLogIn(delegate:delegate)
    }
}
