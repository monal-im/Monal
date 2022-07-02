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
    @State private var showLoadingState = false
    @State private var loadingOverlay = WelcomeLogInOverlayInPlace(headline: "", description: "")
    @State private var timeoutEnabled = false
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
    
    private func checkLoginTimeout() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            if self.timeoutEnabled == true {
                if self.newAccountNo != nil {
                    MLXMPPManager.sharedInstance().clearAccountInfo(forAccountNo: self.newAccountNo!)
                    self.newAccountNo = nil
                }
                self.alertPrompt.title = Text("Timeout Error")
                self.alertPrompt.message = Text("We were not able to connect your account. Please check your credentials and make sure you are connected to the internet.")
                self.timeoutEnabled = false
                self.showLoadingState = false
                self.showAlert = true
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
                                        self.timeoutEnabled = true
                                        checkLoginTimeout()
                                        self.loadingOverlay.headline = NSLocalizedString("Logging in", comment: "")
                                        self.loadingOverlay.description = ""
                                        self.showLoadingState = true
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
                .keyboardShortcut(.escape, modifiers: []))
                .disabled(self.showLoadingState == true)
                .blur(radius: self.showLoadingState == true ? 3 : 0)
                if (self.showLoadingState == true) {
                    loadingOverlay
                }
            }
        }
        .onDisappear {UITableView.appearance().tableHeaderView = nil}
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kXMPPError")).receive(on: RunLoop.main)) { notification in
            if self.errorObserverEnabled == false {
                return
            }
            if let xmppAccount = notification.object as? xmpp, let newAccountNo : NSNumber = self.newAccountNo, let errorMessage = notification.userInfo?["message"] as? String {
                if xmppAccount.accountNo.intValue == newAccountNo.intValue {
                    timeoutEnabled = false
                    showLoadingState = false
                    errorObserverEnabled = false
                    alertPrompt.title = Text("Error")
                    alertPrompt.message = Text(String(format: NSLocalizedString("We were not able to connect your account. Please check your credentials and make sure you are connected to the internet.\n\nTechnical error message: %@", comment: ""), errorMessage))
                    showAlert = true
                    MLXMPPManager.sharedInstance().clearAccountInfo(forAccountNo: newAccountNo)
                    self.newAccountNo = nil
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMLHasConnectedNotice")).receive(on: RunLoop.main)) { notification in
            if let xmppAccount = notification.object as? xmpp, let newAccountNo : NSNumber = self.newAccountNo {
                if xmppAccount.accountNo.intValue == newAccountNo.intValue {
                    self.timeoutEnabled = false
                    self.errorObserverEnabled = false
                    HelperTools.defaultsDB().set(true, forKey: "HasSeenLogin")
                    self.loadingOverlay.headline = NSLocalizedString("Loading contact list", comment: "")
                    self.loadingOverlay.description = ""
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalFinishedCatchup")).receive(on: RunLoop.main)) { notification in
            if let xmppAccount = notification.object as? xmpp, let newAccountNo : NSNumber = self.newAccountNo {
                if xmppAccount.accountNo.intValue == newAccountNo.intValue {
                    self.loadingOverlay.headline = NSLocalizedString("Loading omemo bundles", comment: "")
                    self.loadingOverlay.description = ""
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalUpdateBundleFetchStatus")).receive(on: RunLoop.main)) { notification in
            if let notificationAccountNo = notification.userInfo?["accountNo"] as? NSNumber, let completed = notification.userInfo?["completed"] as? NSNumber, let all = notification.userInfo?["all"] as? NSNumber, let newAccountNo : NSNumber = self.newAccountNo {
                if notificationAccountNo.intValue == newAccountNo.intValue {
                    self.loadingOverlay.headline = NSLocalizedString("Loading omemo bundles", comment: "")
                    self.loadingOverlay.description = String(format: NSLocalizedString("Loading omemo bundles: %@ / %@", comment: ""), completed, all)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalFinishedOmemoBundleFetch")).receive(on: RunLoop.main)) { notification in
            if let notificationAccountNo = notification.userInfo?["accountNo"] as? NSNumber, let newAccountNo : NSNumber = self.newAccountNo {
                if (notificationAccountNo.intValue == newAccountNo.intValue) {
                    showLoadingState = false
                    alertPrompt.title = Text("Success!")
                    alertPrompt.message = Text("You are set up and connected.")
                    loginComplete = true
                    showAlert = true
                }
            }
        }
    }
}

struct WelcomeLogIn_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        WelcomeLogIn(delegate:delegate, hasParentNavigationView: false)
    }
}
