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
        ["XMPPServer": "", "TermsSite_default": ""],
        ["XMPPServer": "yax.im", "TermsSite_default": "https://yaxim.org/yax.im/"],
        ["XMPPServer": "jabber.de", "TermsSite_default": "https://www.jabber.de/impressum/datenschutz/"],
        ["XMPPServer": "xabber.de", "TermsSite_default": "https://www.draugr.de"],
        ["XMPPServer": "trashserver.net", "TermsSite_default": "https://trashserver.net/en/privacy/", "TermsSite_de": "https://trashserver.net/datenschutz/"]
    ]

    static private let xmppFaultyPattern = ".+\\..{2,}$"
    
    @State private var providedServer: String = ""
    @State private var selectedServerIndex = 0

    @State private var showAlert = false
    @State private var activateLinkNavigation = false

    @State private var alertPrompt = AlertPrompt(dismissLabel: Text("Close"))

    private var serverSelectedAlert: Bool {
        alertPrompt.title = Text("No XMPP server!")
        alertPrompt.message = Text("Please select a XMPP server or provide one.")

        return serverSelected
    }

    private var serverProvidedAlert: Bool {
        alertPrompt.title = Text("No XMPP server!")
        alertPrompt.message = Text("Please select a XMPP server or provide one.")

        return serverProvided
    }

    private var xmppServerFaultyAlert: Bool {
        alertPrompt.title = Text("XMPP server domain not valid!")
        alertPrompt.message = Text("Please provide a valid XMPP server domain or select one.")

        return xmppServerFaulty
    }

    private var serverSelected: Bool {
        return selectedServerIndex != 0
    }

    private var serverProvided: Bool {
        return providedServer != ""
    }

    private var xmppServerFaulty: Bool {
        return providedServer.range(of: RegisterAccountSelectServer.xmppFaultyPattern, options:.regularExpression) == nil
    }

    private var buttonColor: Color {
        return !serverSelected && (!serverProvided || xmppServerFaulty) ? .gray : .black
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading) {
            Text("Like email, you can register your account on many sites and talk to anyone. You can use this page to register an account with a selected or provided XMPP server.")
               .padding()

                Form {
                    Picker("Select XMPP-Server", selection: $selectedServerIndex) {
                        // TODO: Replace with actually relevant text ...
                        Text("Dummy Erklärungstext, obwohl hier eigentlich nicht sinnvoll/möglich, da dies ein gewöhnliches iPhone UI Select Element ist, und auf einem Mac wäre das eine ausklappbare Selectbox und da ist kein Text neben den auswählbaren Feldern vorgesehen und wird u. U. merkwürdig aussehen. Dieser 'Unterview' gehört zum Picker, ist also in dem Sinne kein eigenständiger, konfigurierbarer View. Das hier mit dem Text ist sozusagen ein Hack ;-), ein inaktives Select Element missbraucht. Wie gesagt, kann sein dass das auf dem Mac gar nicht gut kommt.")
                            .padding()
                            .onTapGesture {
                                return
                            }
                        ForEach (RegisterAccountSelectServer.XMPPServer.indices, id: \.self) {
                            if $0 != 0 {
                                Text(RegisterAccountSelectServer.XMPPServer[$0]["XMPPServer"] ?? "").tag($0)
                            }
                        }
                    }
                    .onAppear(perform: {
                        if selectedServerIndex  != 0 {
                            providedServer = ""
                        }
                    })
 
                    TextField("Provide XMPP-Server", text: Binding(get: { self.providedServer }, set: { string in self.providedServer = string.lowercased() }))
                        .disableAutocorrection(true)
                        .onChange(of: providedServer) {
                            tag in
                            if providedServer != "" {
                                selectedServerIndex = 0
                            }
                        }
                                    
                    Button(action: {
                        showAlert = !serverSelectedAlert && (!serverProvidedAlert || xmppServerFaultyAlert)
                        activateLinkNavigation = !showAlert
                    }){
                        HStack {
                            Text("Register Account")
                                .foregroundColor(buttonColor)
                            
                            NavigationLink(destination: RegisterAccount($selectedServerIndex, $providedServer), isActive: $activateLinkNavigation) {
                            }
                            .disabled(true)
                        }
                    }
                    .alert(isPresented: $showAlert) {
                        Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton: .default(alertPrompt.dismissLabel))
                    }
                                        
                    Text("The selectable XMPP servers are public servers which are not affiliated to Monal. This registration page is provided for convenience only.")
                        .font(.system(size: 13))
                        .padding(.vertical, 10)
                }
                .frame(height: 285)
                .textFieldStyle(.roundedBorder)
            }
        }
        
        .navigationTitle("Register")
    }
}

struct RegisterAccountSelectServer_Previews: PreviewProvider {
    static var previews: some View {
        RegisterAccountSelectServer()
    }
}
