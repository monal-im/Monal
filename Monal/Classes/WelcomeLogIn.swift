//
//  WelcomeLogIn.swift
//  Monal
//
//  Created by CC on 22.04.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import SwiftUI

struct WelcomeLogIn: View {
    static private let credFaultyPattern = ".+@.+\\..{2,}$"

    @State private var account: String = ""
    @State private var password: String = ""

    @State private var showAlert = false
    @State private var showQRCodeScanner = false
    
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    private var credentialsEnteredAlert: Bool {
        alertTitle = "No Empty Values!"
        alertMessage = "Please make sure you have entered a username, password."

        return credentialsEntered
    }

    private var credentialsFaultyAlert: Bool {
        alertTitle = "Invalid Credentials!"
        alertMessage = "Your XMPP account should be in in the format user@domain. For special configurations, use manual setup."

        return credentialsFaulty
    }

    private var credentialsExistAlert: Bool {
        alertTitle = "Duplicate Account!"
        alertMessage = "This account already exists on this instance."
        
        return credentialsExist
    }

    private var credentialsEntered: Bool {
        return !account.isEmpty && !password.isEmpty
    }
    
    private var credentialsFaulty: Bool {
        return account.range(of: WelcomeLogIn.credFaultyPattern, options:.regularExpression) == nil
    }
    
    private var credentialsExist: Bool {
        // To be replaced by actual test if user already exist on the monal instance, based on entered account or qrcode account
        return false
    }

    private var buttonColor: Color {
        return !credentialsEntered || credentialsFaulty ? .gray : .blue
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading) {
                    HStack () {
                        Image(decorative: "AppLogo")
                            .resizable()
                            .frame(width: CGFloat(120), height: CGFloat(120), alignment: .center)
                            .padding()
                        
                        Text("Log in to your existing account or register an account. If required you will find more advanced options in Monal settings.")
                            .padding()
                        
                    }
                    .frame(maxWidth: .infinity)
                    
                    Form {
                        TextField("user@domain", text: Binding(
                            get: { self.account },
                            set: { string in self.account = string.lowercased() })
                        )
                        .disableAutocorrection(true)
                        
                        SecureField("Password", text: $password)
                        
                        HStack() {
                            Button(action: {
                                showAlert = !credentialsEnteredAlert || credentialsFaultyAlert || credentialsExistAlert
                                
                                if !showAlert {
                                    // Code/Action for actual login via account and password
                                }
                            }){
                                Text("Login")
                                    .frame(maxWidth: .infinity)
                                    .padding(9.0)
                                    .background(Color(red: 0.897, green: 0.878, blue: 0.878))
                                    .foregroundColor(buttonColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .alert(isPresented: $showAlert) {
                                Alert(title: Text("\(alertTitle)"), message: Text("\(alertMessage)"), dismissButton: .default(Text("Close")))
                            }

                            Button(action: {
                                showAlert = credentialsExistAlert
                                showQRCodeScanner = !showAlert
                            }){
                                Image(systemName: "qrcode")
                                    .frame(maxHeight: .infinity)
                                    .padding(9.0)
                                    .background(Color(red: 0.897, green: 0.878, blue: 0.878))
                                    .foregroundColor(.black)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .alert(isPresented: $showAlert) {
                                Alert(title: Text("\(alertTitle)"), message: Text("\(alertMessage)"), dismissButton: .default(Text("Close")))
                            }
                            .sheet(isPresented: $showQRCodeScanner) {
                                Text("QR-Code Scanner").font(.largeTitle.weight(.bold))
                                // Get existing credentials from QR and put values in account and password
                                QRCodeScannerView($account, $password, $showQRCodeScanner)
                            }

                        }
                        
                        NavigationLink(destination: RegisterAccountSelectServer()) {
                            Text("Register")
                        }
                        
                        Button(action: {
                            // Code/Action for jump to whatever view after not setting up an account ...
                        }){
                           Text("Set up account later")
                               .frame(maxWidth: .infinity)
                               .padding(.top, 10.0)
                               .padding(.bottom, 9.0)
                        }
                    }
                    .frame(minHeight: 310)
                    .textFieldStyle(.roundedBorder)
                }
            }
            
            .navigationTitle("Welcome")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct WelcomeLogIn_Previews: PreviewProvider {
    static var previews: some View {
        WelcomeLogIn()
    }
}
