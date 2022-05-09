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

    static private let xmppFaultyPattern = ".+\\..{2,}$"
    
    @State private var providedServer: String = ""
    @State private var selectedServerIndex = 0

    @State private var showAlert = false
    @State private var activateLinkNavigation = false

    @State private var alertTitle = ""
    @State private var alertMessage = ""

    private var serverSelectedAlert: Bool {
        alertTitle = "No XMPP server!"
        alertMessage = "Please select a XMPP server or provide one."

        return serverSelected
    }

    private var serverProvidedAlert: Bool {
        alertTitle = "No XMPP server!"
        alertMessage = "Please select a XMPP server or provide one."

        return serverProvided
    }

    private var xmppServerFaultyAlert: Bool {
        alertTitle = "XMPP server domain not valid!"
        alertMessage = "Please provide a valid XMPP server domain or select one."

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
        return !serverSelected && (!serverProvided || xmppServerFaulty) ? .gray : .blue
    }

    var body: some View {
        ScrollView {
        VStack(alignment: .leading) {
            Text("Like email, you can create your account on many sites and talk to anyone. You can use this page to create an account with your selected or provided XMPP server.")
               .padding()

                Form {
                    Picker("Select XMPP-Server", selection: $selectedServerIndex) {
                        Text("Dummy Erklärungstext, obwohl hier eigentlich nicht sinnvoll/möglich, da dies ein gewöhnliches iPhone UI Select Element ist, und auf einem Mac wäre das eine ausklappbare Selectbox und da ist kein Text neben den auswählbaren Feldern vorgesehen und wird u. U. merkwürdig aussehen. Dieser 'Unterview' gehört zum Picker, ist also in dem Sinne kein eigenständiger, konfigurierbarer View. Das hier mit dem Text ist sozusagen ein Hack ;-), ein inaktives Select Element missbraucht. Wie gesagt, kann sein dass das auf dem Mac gar nicht gut kommt.")
                            .padding()
                            .onTapGesture {
                                return
                            }
                        ForEach (RegisterAccountSelectServer.XMPPServer.indices, id: \.self) {
                            if $0 != 0 {
                                Text("\(RegisterAccountSelectServer.XMPPServer[$0]["XMPPServer"] ?? "")").tag($0)
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
                            Text("Create Account")
                                .foregroundColor(buttonColor)
                            
                            // Dummy to get the NavigationLink arrow at the end
                            NavigationLink(destination: DummyView()) {
                            }
                            .disabled(true)
                        }
                    }
                    .alert(isPresented: $showAlert) {
                        Alert(title: Text("\(alertTitle)"), message: Text("\(alertMessage)"), dismissButton: .default(Text("Close")))
                    }
                                        
                    Text("The selectable XMPP servers are public servers which are not affiliated to Monal. This registration page is provided for convenience only.")
                        .font(.system(size: 13))
                        .padding(.vertical, 10)
                }
                .frame(height: 500)
                .textFieldStyle(.roundedBorder)
            
                // Hidden NavigationLink, gets activated and executed by "Create Account" Button
                NavigationLink(destination: RegisterAccount($selectedServerIndex, $providedServer), isActive: $activateLinkNavigation) {
                }
                .disabled(true).hidden()
            }
        }
        
        .navigationTitle("Register")
    }
}

struct DummyView: View {
    var body: some View {
        EmptyView()
    }
}

struct RegisterAccountSelectServer_Previews: PreviewProvider {
    static var previews: some View {
        RegisterAccountSelectServer()
    }
}
