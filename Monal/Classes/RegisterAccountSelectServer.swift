//
//  RegisterAccountSelectServer.swift
//  Monal
//
//  Created by CC on 22.04.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import SwiftUI

struct RegisterAccountSelectServer: View {
    static let XMPPServer: [Dictionary<String, String>] = [
        ["XMPPServer": "", "TermsSite": ""],
        ["XMPPServer": "yax.im", "TermsSite": "https://yaxim.org/yax.im/"],
        ["XMPPServer": "jabber.de", "TermsSite": "https://www.jabber.de/impressum/datenschutz/"],
        ["XMPPServer": "xabber.de", "TermsSite": "https://www.draugr.de"],
    ]
        
    @State private var providedServer: String = ""
    @State private var selectedServerIndex = 0

    @State private var showAlert = false

    private var serverSelectedOrProvided: Bool {
        return selectedServerIndex != 0 || providedServer != ""
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Like email, you can create your account on many sites and talk to anyone. You can use this page to create an account with your selected or provided XMPP server.")
               .padding()

            Form {
                List {
                    Picker("Select XMPP-Server", selection: $selectedServerIndex) {
                        ForEach (RegisterAccountSelectServer.XMPPServer.indices, id: \.self) {
                            if $0 != 0 {
                                Text("\(RegisterAccountSelectServer.XMPPServer[$0]["XMPPServer"] ?? "")").tag($0)
                            }
                        }
                    }
                    .onChange(of: selectedServerIndex) {tag in providedServer = ""}
                }

                TextField("Provide XMPP-Server", text: $providedServer)
                    .onTapGesture {
                        selectedServerIndex = 0
                    }
                    .onChange(of: providedServer) {
                        tag in selectedServerIndex = 0
                    }
                    
                //TextField("Provide XMPP-Server", text: $providedServer).onChange(of: providedServer) {
                //    tag in selectedServerIndex = 0
                //}
                
                // Works only if view is refreshed due to some State change ...
                if serverSelectedOrProvided {
                    NavigationLink(destination: RegisterAccount($selectedServerIndex, $providedServer)) {
                        Text("Create Account")
                    }
                }
                else {
                    Button(action: {
                        showAlert = true
                    }){
                        Text("Create Account")
                            .foregroundColor(Color.gray)
                    }
                    .alert(isPresented: $showAlert) {
                        Alert(title: Text("No XMPP server!"), message: Text("Please select a XMPP server or provide one."), dismissButton: .default(Text("Close")))
                    }
                }
                                    
                Text("The selectable XMPP servers are public servers which are not affiliated to Monal. This registration page is provided for convenience only.")
                    .font(.system(size: 13))
                    .padding(.vertical, 10)
            }

            .textFieldStyle(.roundedBorder)

            .navigationTitle("Registration")
        }
    }
}

struct RegisterAccountSelectServer_Previews: PreviewProvider {
    static var previews: some View {
        RegisterAccountSelectServer()
    }
}
