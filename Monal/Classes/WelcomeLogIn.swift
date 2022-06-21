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
    
    var body: some View {
        NavigationView {
            ZStack {
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
                                        // TODO: Code/Action for actual login via jid and password and jump to whatever view after successful login
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
                                    Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton: .default(alertPrompt.dismissLabel))
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
                            
                            NavigationLink(destination: RegisterAccount()) {
                                Text("Register")
                            }
                            
                            Button(action: {
                                self.delegate.dismiss()
                            }){
                               Text("Set up account later")
                                   .frame(maxWidth: .infinity)
                                   .padding(.top, 10.0)
                                   .padding(.bottom, 9.0)
                            }
                        }
                        .frame(minHeight: 310)
                        .textFieldStyle(.roundedBorder)
                        .onAppear {UITableView.appearance().tableHeaderView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 30))}
                    }
                }

                .navigationTitle("Welcome")

                .navigationBarBackButtonHidden(true)                   // will not be shown because swiftui does not know we navigated here from UIKit
                .navigationBarItems(leading: Button(action : {
                    self.delegate.dismiss()
                }){
                    Image(systemName: "arrow.backward")
                }
                .keyboardShortcut(.escape, modifiers: []))
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onDisappear {UITableView.appearance().tableHeaderView = nil}

    }
}

struct WelcomeLogIn_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        WelcomeLogIn(delegate:delegate)
    }
}
