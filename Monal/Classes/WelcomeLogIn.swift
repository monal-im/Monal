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
    var delegate: SheetDismisserProtocol
    
    static private let credFaultyPattern = "^.+@.+\\..{2,}$"
    
    @State private var jid: String = ""
    @State private var password: String = ""

    @State private var showAlert = false
    @State private var showQRCodeScanner = false

    // login related
    @State private var loadingOverlay = LoadingOverlay(headline: "", description: "")
    @State private var currentTimeout : DispatchTime? = nil
    @State private var errorObserverEnabled = false
    @State private var newAccountNo: NSNumber? = nil
    @State private var loginComplete = false
    
    @State private var alertPrompt = AlertPrompt(dismissLabel: Text("Close"))
    
    private var credentialsEnteredAlert: Bool {
        alertPrompt.title = Text("No Empty Values!")
        alertPrompt.message = Text("Please make sure you have entered a username and password.")
        return credentialsEntered
    }

    private var credentialsFaultyAlert: Bool {
        alertPrompt.title = Text("Invalid Credentials!")
        alertPrompt.message = Text("Your XMPP jid should be in in the format user@domain.tld. For special configurations, use manual setup.")
        return credentialsFaulty
    }

    private var credentialsExistAlert: Bool {
        alertPrompt.title = Text("Duplicate jid!")
        alertPrompt.message = Text("This jid already exists on this instance.")
        return credentialsExist
    }

    private func showTimeoutAlert() {
        hideLoadingOverlay()
        alertPrompt.title = Text("Timeout Error")
        alertPrompt.message = Text("We were not able to connect your account. Please check your credentials and make sure you are connected to the internet.")
        showAlert = true
    }

    private func showSuccessAlert() {
        hideLoadingOverlay()
        alertPrompt.title = Text("Success!")
        alertPrompt.message = Text("You are set up and connected.")
        showAlert = true
    }

    private func showLoginErrorAlert(errorMessage: String) {
        hideLoadingOverlay()
        alertPrompt.title = Text("Error")
        alertPrompt.message = Text(String(format: NSLocalizedString("We were not able to connect your account. Please check your credentials and make sure you are connected to the internet.\n\nTechnical error message: %@", comment: ""), errorMessage))
        showAlert = true
    }

    private func showLoadingOverlay(headline: String, description: String) {
        loadingOverlay.headline = headline
        loadingOverlay.description = description
        loadingOverlay.enabled = true
    }

    private func hideLoadingOverlay() {
        loadingOverlay.headline = ""
        loadingOverlay.description = ""
        loadingOverlay.enabled = false
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
            if newTimeout == self.currentTimeout {
                if self.newAccountNo != nil {
                    MLXMPPManager.sharedInstance().removeAccount(forAccountNo: self.newAccountNo!)
                    self.newAccountNo = nil
                }
                self.currentTimeout = nil
                showTimeoutAlert()
            }
        }
    }

    let hasParentNavigationView : Bool

    var body: some View {
        NavigationView {
            ZStack(alignment: .center) {
                Color(UIColor.systemGroupedBackground).ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading) {
                        HStack () {
                            Image(decorative: "AppLogo")
                                .resizable()
                                .frame(width: CGFloat(120), height: CGFloat(120), alignment: .center)
                                .padding()
                            
                            Text("Log in to your existing account or register a new account. If required you will find more advanced options in Monal settings.")
                                .padding()
                                .padding(.leading, -16.0)
                            
                        }
                        .frame(maxWidth: .infinity)
                        .background(Color(UIColor.systemBackground))

                        Form {
                            TextField("user@domain.tld", text: Binding(
                                get: { self.jid },
                                set: { string in self.jid = string.lowercased() })
                            )
                            .disableAutocorrection(true)
                            .keyboardType(.emailAddress)
                            
                            SecureField("Password", text: $password)
                            
                            HStack() {
                                Button(action: {
                                    showAlert = !credentialsEnteredAlert || credentialsFaultyAlert || credentialsExistAlert

                                    if (!showAlert) {
                                        startLoginTimeout()
                                        showLoadingOverlay(
                                            headline: NSLocalizedString("Logging in", comment: ""),
                                            description: "")
                                        self.errorObserverEnabled = true
                                        self.newAccountNo = MLXMPPManager.sharedInstance().login(self.jid, password: self.password)
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
                            
                            NavigationLink(destination: RegisterAccount(delegate: self.delegate)) {
                                Text("Register")
                            }
                            
                            if(self.hasParentNavigationView == false) {
                                Button(action: {
                                    self.delegate.dismiss()
                                }){
                                    Text("Set up account later")
                                        .frame(maxWidth: .infinity)
                                        .padding(.top, 10.0)
                                        .padding(.bottom, 9.0)
                                }
                            }
                        }
                        .frame(minHeight: 310)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {UITableView.appearance().tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 30))}
                    }
                }

                // TODO fix those workarounds as soon as settings are not a storyboard anymore
                .navigationBarHidden(UIDevice.current.userInterfaceIdiom == .phone)
                .navigationBarTitle(Text("Welcome"), displayMode: self.hasParentNavigationView == true ? .inline : .automatic)
                .navigationBarHidden(false)
                .navigationBarBackButtonHidden(true) // will not be shown because swiftui does not know we navigated here from UIKit
                .navigationBarItems(leading: self.hasParentNavigationView == true ? nil : Button(action : {
                        self.delegate.dismiss()
                    }){
                        Image(systemName: "arrow.backward")
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                )
                .disabled(self.loadingOverlay.enabled == true)
                .blur(radius: self.loadingOverlay.enabled == true ? 3 : 0)
                loadingOverlay
            }
        }
        .navigationViewStyle(.stack)
        .onDisappear {UITableView.appearance().tableHeaderView = nil}
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kXMPPError")).receive(on: RunLoop.main)) { notification in
            if self.errorObserverEnabled == false {
                return
            }
            if let xmppAccount = notification.object as? xmpp, let newAccountNo : NSNumber = self.newAccountNo, let errorMessage = notification.userInfo?["message"] as? String {
                if xmppAccount.accountNo.intValue == newAccountNo.intValue {
                    currentTimeout = nil // <- disable timeout on error
                    errorObserverEnabled = false
                    showLoginErrorAlert(errorMessage: errorMessage)
                    MLXMPPManager.sharedInstance().removeAccount(forAccountNo: newAccountNo)
                    self.newAccountNo = nil
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMLHasConnectedNotice")).receive(on: RunLoop.main)) { notification in
            if let xmppAccount = notification.object as? xmpp, let newAccountNo : NSNumber = self.newAccountNo {
                if xmppAccount.accountNo.intValue == newAccountNo.intValue {
                    currentTimeout = nil // <- disable timeout on successful connection
                    self.errorObserverEnabled = false
                    HelperTools.defaultsDB().set(true, forKey: "HasSeenLogin")
                    showLoadingOverlay(
                        headline: NSLocalizedString("Loading contact list", comment: ""),
                        description: "")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalFinishedCatchup")).receive(on: RunLoop.main)) { notification in
            if let xmppAccount = notification.object as? xmpp, let newAccountNo : NSNumber = self.newAccountNo {
                if xmppAccount.accountNo.intValue == newAccountNo.intValue {
#if !DISABLE_OMEMO
                    showLoadingOverlay(
                        headline: NSLocalizedString("Loading omemo bundles", comment: ""),
                        description: "")
#endif
#if DISABLE_OMEMO
                    self.loginComplete = true
                    showSuccessAlert()
#endif
                }
            }
        }
#if !DISABLE_OMEMO
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalUpdateBundleFetchStatus")).receive(on: RunLoop.main)) { notification in
            if let notificationAccountNo = notification.userInfo?["accountNo"] as? NSNumber, let completed = notification.userInfo?["completed"] as? NSNumber, let all = notification.userInfo?["all"] as? NSNumber, let newAccountNo : NSNumber = self.newAccountNo {
                if notificationAccountNo.intValue == newAccountNo.intValue {
                    showLoadingOverlay(
                        headline: NSLocalizedString("Loading omemo bundles", comment: ""),
                        description: String(format: NSLocalizedString("Loading omemo bundles: %@ / %@", comment: ""), completed, all))
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalFinishedOmemoBundleFetch")).receive(on: RunLoop.main)) { notification in
            if let notificationAccountNo = notification.userInfo?["accountNo"] as? NSNumber, let newAccountNo : NSNumber = self.newAccountNo {
                if (notificationAccountNo.intValue == newAccountNo.intValue) {
                    self.loginComplete = true
                    showSuccessAlert()
                }
            }
        }
#endif
    }
}

struct WelcomeLogIn_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        WelcomeLogIn(delegate:delegate, hasParentNavigationView: false)
    }
}
