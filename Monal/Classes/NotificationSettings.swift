//
//  NotificationSettings.swift
//  Monal
//
//  Created by Jan on 02.05.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import SwiftUI
import monalxmpp
import OrderedCollections

struct NotificationSettings: View {
    @ViewBuilder
    func buildLabel(_ description: Text, isWorking: Bool) -> some View {
        if(isWorking == true) {
            Label(title: {
                description
            }, icon: {
                Image(systemName: "checkmark.seal")
                    .foregroundColor(.green)
            })
        } else {
            Label(title: {
                description
            }, icon: {
                Image(systemName: "xmark.seal")
                    .foregroundColor(.red)
            })
        }
    }

    var delegate: SheetDismisserProtocol
    
    private let applePushEnabled: Bool
    private let applePushToken: String
    private let xmppAccountInfo: [xmpp]

    private let availablePushServers: Dictionary<String, String>

    @State private var pushPermissionEnabled = false // state because we get this value through an async call
    @State private var showPushToken = false

    @State private var selectedPushServer: String

    var body: some View {
        Form {
            Group {
                Section(header: Text("Status").font(.title3)) {
                    VStack(alignment: .leading) {
                        buildLabel(Text("Apple Push Service"), isWorking: self.applePushEnabled);
                        Divider()
                        Text("Apple push service should always be on. If it is off, your device can not talk to Apple's server.").font(.footnote)
                    }.onTapGesture(count: 5, perform: {
                        showPushToken = true
                    }).alert(isPresented: $showPushToken) {
                        (self.applePushEnabled == true) ?
                        Alert(
                            title: Text("Apple Push Token"),
                            message: Text(self.applePushToken),
                            primaryButton: .default(Text("Copy to clipboard"),
                            action: {
                                UIPasteboard.general.string = self.applePushToken;
                            }),
                            secondaryButton: .destructive(Text("Close")))
                        :
                            Alert(title: Text("Apple Push Token is not available!"))
                    }
                }
                Section {
                    VStack(alignment: .leading) {
                        buildLabel(Text("Can Show Notifications"), isWorking: self.pushPermissionEnabled);
                        Divider()
                        Text("If Monal can't show notifications, you will not see alerts when a message arrives. This happens if you tapped 'Decline' when Monal first asked permission. Fix it by going to iOS Settings -> Monal -> Notifications and select 'Allow Notifications'.").font(.footnote)
                    }
                }
                if(self.xmppAccountInfo.count > 0) {
                    Section {
                        VStack(alignment: .leading) {
                            ForEach(self.xmppAccountInfo, id: \.self) { account in
                                buildLabel(Text(account.connectionProperties.identity.jid), isWorking: account.connectionProperties.pushEnabled)
                                Divider()
                            }
                            Text("If this is off your device could not activate push on your xmpp server, make sure to have configured it to support XEP-0357.").font(.footnote)
                        }
                    }
                } else {
                    Section {
                        Text("No accounts set up currently").font(.footnote)
                    }.opacity(0.5)
                }
            }
            Section(header: Text("Pushserver Region").font(.title3)) {
                Picker("Push Server", selection: $selectedPushServer) {
                    ForEach(self.availablePushServers.sorted(by: >), id: \.key) { pushServerFqdn, pushServerName in
                        Text(pushServerName).tag(pushServerFqdn)
                    }
                }.pickerStyle(.menu)//.menuStyle(.borderlessButton)
                .onChange(of: selectedPushServer) { pushServerFqdn in
                    DDLogDebug("Selected \(pushServerFqdn) as push server")
                    HelperTools.defaultsDB().setValue(pushServerFqdn, forKey: "selectedPushServer")
                    // enable push again to switch to the selected server
                    for account in self.xmppAccountInfo {
                        account.enablePush()
                    }
                }
            }
        }
        .navigationBarTitle(Text("Notifications"))
        .onAppear(perform: {
            UNUserNotificationCenter.current().getNotificationSettings { (settings) -> Void in
                self.pushPermissionEnabled = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional);
            }
        });
    }

    init(delegate: SheetDismisserProtocol) {
        self.applePushEnabled = MLXMPPManager.sharedInstance().hasAPNSToken;
        self.applePushToken = MLXMPPManager.sharedInstance().pushToken;
        self.xmppAccountInfo = MLXMPPManager.sharedInstance().connectedXMPP as! [xmpp]
        self.delegate = delegate

        // push server selector
        self.availablePushServers = HelperTools.getAvailablePushServers()
        self.selectedPushServer = HelperTools.defaultsDB().object(forKey: "selectedPushServer") as! String
    }
}

struct PushSettings_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        NotificationSettings(delegate:delegate)
    }
}
