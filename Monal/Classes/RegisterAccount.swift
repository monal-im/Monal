//
//  RegisterAccount.swift
//  Monal
//
//  Created by CC on 22.04.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import SwiftUI

struct RegisterAccount: View {
    static private let credFaultyPattern = ".*@.*"

    @Binding private var selectedServerIndex : Int
    @Binding private var providedServer : String

    @State private var username: String = ""
    @State private var password: String = ""
        
    @State private var showAlert = false

    @State private var alertTitle = ""
    @State private var alertMessage = ""

    private var actualServer: String
    private var actualTermsUrl: String
    private var showTermsUrl = false
    
    private var credentialsEntered: Bool {
        alertTitle = "No Empty Values!"
        alertMessage = "Please make sure you have entered a username, password."
        
        return !username.isEmpty && !password.isEmpty
    }

    private var credentialsFaulty: Bool {
        alertTitle = "Invalid Username!"
        alertMessage = "The username does not need to have an @ symbol. Please try again."

        return username.range(of: RegisterAccount.credFaultyPattern, options: .regularExpression) != nil
    }

    private var buttonColor: Color {
            return !credentialsEntered || credentialsFaulty ? .gray : .blue
    }
    
    init(_ selectedServerIndex: Binding<Int>, _ providedServer: Binding<String>) {
        self._selectedServerIndex = selectedServerIndex
        self._providedServer = providedServer
        actualServer = providedServer.wrappedValue
        actualTermsUrl = "None"
        
        if (actualServer == "") {
            actualServer = "None"
            actualTermsUrl = "None"
            
            if let temp = RegisterAccountSelectServer.XMPPServer[selectedServerIndex.wrappedValue]["XMPPServer"] {
                if (temp != "") {
                    actualServer = temp
 
                    if let temp = RegisterAccountSelectServer.XMPPServer[selectedServerIndex.wrappedValue]["TermsSite"] {
                        if (temp != "") {
                            actualTermsUrl = temp
                            showTermsUrl = true
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Choose a username and a password to register an account on selected server \(actualServer).")
               .padding()
            
            Form {
                Text("Register for \(actualServer)")
                TextField("Username", text: $username)
                SecureField("Password", text: $password)
                
                Button(action: {
                    showAlert = !credentialsEntered || credentialsFaulty
                    
                    if !showAlert {
                        // Code/Action for registration ...
                    }
                }){
                    Text("Register")
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
                
                if(showTermsUrl) {
                    Link("Terms of use",
                        destination: URL(string: "\(actualTermsUrl)")!)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30.0)
                            .padding(.bottom, 9.0)
                }
                
            }
            
            .textFieldStyle(.roundedBorder)
            
            .navigationTitle("Create Account")
        }
    }
}

struct RegisterAccount_Previews: PreviewProvider {
    @State private var providedServer: String = ""
    @State private var selectedServerIndex = 0

    static var previews: some View {
        RegisterAccount(RegisterAccount_Previews().$selectedServerIndex, RegisterAccount_Previews().$providedServer)
    }
}
