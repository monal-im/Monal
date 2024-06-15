//
//  NotificationDebugging.swift
//  Monal
//
//  Created by Jan on 02.05.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import OrderedCollections

struct NotificationDebugging: View {
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
                        buildNotificationStateLabel(Text("Apple Push Service"), isWorking: self.applePushEnabled);
                        Divider()
                        Text("Apple push service should always be on. If it is off, your device can not talk to Apple's server.").foregroundColor(Color(UIColor.secondaryLabel)).font(.footnote)
                        if !self.applePushEnabled, let apnsError = MLXMPPManager.sharedInstance().apnsError {
                            Text("Error: \(String(describing:apnsError))").foregroundColor(.red).font(.footnote)
                        }
                    }.onTapGesture(count: 2, perform: {
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
                        buildNotificationStateLabel(Text("Can Show Notifications"), isWorking: self.pushPermissionEnabled);
                        Divider()
                        Text("If Monal can't show notifications, you will not see alerts when a message arrives. This happens if you tapped 'Decline' when Monal first asked permission. Fix it by going to iOS Settings -> Monal -> Notifications and select 'Allow Notifications'.").foregroundColor(Color(UIColor.secondaryLabel)).font(.footnote)
                    }
                }
                if(self.xmppAccountInfo.count > 0) {
                    Section {
                        VStack(alignment: .leading) {
                            ForEach(self.xmppAccountInfo, id: \.self) { account in
                                buildNotificationStateLabel(Text(account.connectionProperties.identity.jid), isWorking: account.connectionProperties.pushEnabled)
                                Divider()
                            }
                            Text("If this is off your device could not activate push on your xmpp server, make sure to have configured it to support XEP-0357.").foregroundColor(Color(UIColor.secondaryLabel)).font(.footnote)
                        }
                    }
                } else {
                    Section {
                        Text("No accounts set up currently").foregroundColor(Color(UIColor.secondaryLabel)).font(.footnote)
                    }.opacity(0.5)
                }
            }
            Section(header: Text("Pushserver Region").font(.title3)) {
                Picker(selection: $selectedPushServer, label: Text("Push Server")) {
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
#if DEBUG
            Section(header: Text("Debugging").font(.title3)) {
                Button("Reregister push token") {
                    UIApplication.shared.unregisterForRemoteNotifications()
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
#endif
        }
        .navigationBarTitle(Text("Notifications"))
        .onAppear(perform: {
            UNUserNotificationCenter.current().getNotificationSettings { (settings) -> Void in
                self.pushPermissionEnabled = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional);
            }
        });
    }

    init() {
        self.applePushEnabled = MLXMPPManager.sharedInstance().hasAPNSToken;
        self.applePushToken = MLXMPPManager.sharedInstance().pushToken;
        self.xmppAccountInfo = MLXMPPManager.sharedInstance().connectedXMPP as! [xmpp]

        // push server selector
        self.availablePushServers = HelperTools.getAvailablePushServers()
        self.selectedPushServer = HelperTools.defaultsDB().object(forKey: "selectedPushServer") as! String
    }
}

struct PushSettings_Previews: PreviewProvider {
    static var previews: some View {
        NotificationSettings()
    }
}
