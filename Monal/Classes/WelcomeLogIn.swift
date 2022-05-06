//
//  WelcomeLogIn.swift
//  Monal
//
//  Created by CC on 22.04.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import SwiftUI

struct WelcomeLogIn: View {
    var delegate: SheetDismisserProtocol
    
    static private let credFaultyPattern = ".+@.+\\..+$"

    @State private var account: String = ""
    @State private var password: String = ""
    
    @State private var showAlert = false
    @State private var showFaultyAlert = false
    
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    private var credentialsEntered: Bool {
        alertTitle = "No Empty Values!"
        alertMessage = "Please make sure you have entered a username, password."

        return !account.isEmpty && !password.isEmpty
    }
    
    private var credentialsFaulty: Bool {
        alertTitle = "Invalid Credentials!"
        alertMessage = "Your XMPP account should be in in the format user@domain. For special configurations, use manual setup."

        return account.range(of: WelcomeLogIn.credFaultyPattern, options:.regularExpression) == nil
    }
    
    private var buttonColor: Color {
        return !credentialsEntered || credentialsFaulty ? .gray : .blue
    }
    
    var body: some View {
        NavigationView {
            VStack(alignment: .center) {
                Image("AppLogo")
                   .resizable()
                   .frame(width: CGFloat(150), height: CGFloat(150), alignment: .center)
                   .padding()
               
                Text("Log in to your existing account or register an account. If required you will find more advanced options in Monal settings via 'Add account (advanced)'")
                   .padding()
                
                Form {
                    TextField("user@domain", text: $account)
                    SecureField("Password", text: $password)
                    
                    HStack() {
                        Button(action: {
                            showAlert = !credentialsEntered || credentialsFaulty
                            
                            if !showAlert {
                                // Code/Action for actual login ...
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
                             // Code for Login via QR
                        }){
                            Image(systemName: "qrcode")
                                .frame(width: CGFloat(35), height: CGFloat(35), alignment: .center)
                                .background(Color(red: 0.897, green: 0.878, blue: 0.878))
                                .foregroundColor(.black)
                                .clipShape(Circle())
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    
                    NavigationLink(destination: RegisterAccountSelectServer()) {
                        Text("Register")
                    }
                    
                    Button(action: {
                        // Code/Action for jump to whatever view after not setting up an account ...
                    }){
                       Text("Set up account later")
                           .frame(maxWidth: .infinity)
                           .padding(.top, 30.0)
                           .padding(.bottom, 9.0)

                    }
                }

                .textFieldStyle(.roundedBorder)

            }
            .navigationBarBackButtonHidden(true)                   // will not be shown because swiftui does not know we navigated here from UIKit
            .navigationBarItems(leading: Button(action : {
                self.delegate.dismiss()
            }){
                Image(systemName: "arrow.backward")
            }.keyboardShortcut(.escape, modifiers: []))
        }
    }
}

struct WelcomeLogIn_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        WelcomeLogIn(delegate:delegate)
    }
}
