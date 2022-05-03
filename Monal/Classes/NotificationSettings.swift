//
//  NotificationSettings.swift
//  Monal
//
//  Created by Jan on 02.05.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import SwiftUI
import monalxmpp

private struct AccountPushInfo : Identifiable {
    let accountName: String
    let pushEnabled: Bool
    var id: String { accountName }
}

struct NotificationSettings: View {
    func buildLabel(_ description: String, isLocalized: Bool, isWorking: Bool) -> some View {
        let labelText = (isLocalized == true) ? NSLocalizedString(description, comment: "") : description;
        if(isWorking == true) {
            return Label(labelText, systemImage: "checkmark.seal").accentColor(.green);
        } else {
            return Label(labelText, systemImage: "xmark.seal").accentColor(.red);
        }
    }

    private let xmppAccounts: [AccountPushInfo]
    private let applePushEnabled: Bool
    private let applePushToken: String

    @State var pushPermissionEnabled = false // state because we get this value through an async call
    @State var showPushToken = false
    @State var pushServer = 0

    var body: some View {
        NavigationView {
            Form {
                Group {
                    Section(header: Text(NSLocalizedString("Status", comment: "")).font(.title3)) {
                        VStack(alignment: .leading) {
                            buildLabel("Apple Push Service", isLocalized: true, isWorking: self.applePushEnabled);
                            Divider()
                            Text(NSLocalizedString("Apple push service should always be on. If it is off, your device can not talk to Apple's server.", comment: "")).font(.footnote)
                        }.onTapGesture(count: 5, perform: {
                            showPushToken = true
                        }).alert(isPresented: $showPushToken) {
                            (self.applePushEnabled == true) ?
                                Alert(title: Text(NSLocalizedString("Apple Push Token", comment: "")), message: Text(self.applePushToken)) :
                                Alert(title: Text(NSLocalizedString("Apple Push Token is not available!", comment: "")))
                        }
                    }
                    Section {
                        VStack(alignment: .leading) {
                            buildLabel("Can Show Notifications", isLocalized: true, isWorking: self.pushPermissionEnabled);
                            Divider()
                            Text(NSLocalizedString("If Monal can't show notifications, you will not see alerts when a message arrives. This happens if you tapped 'Decline' when Monal first asked permission. Fix it by going to iOS Settings -> Monal -> Notifications and select 'Allow Notifications'.", comment: "")).font(.footnote)
                        }
                    }
                    if(self.xmppAccounts.count > 0) {
                        Section {
                            VStack(alignment: .leading) {
                                ForEach(self.xmppAccounts) { account in
                                    buildLabel(account.accountName, isLocalized: false, isWorking: account.pushEnabled)
                                }
                                Divider()
                                Text(NSLocalizedString("If this is off your device could not activate push on your xmpp server, make sure to have configured it to support XEP-0357.", comment: "")).font(.footnote)
                            }
                        }
                    } else {
                        Section {
                            Text(NSLocalizedString("No accounts set up currently", comment: "")).font(.footnote)
                        }.opacity(0.5)
                    }
                }
                Section(header: Text(NSLocalizedString("Selected Region", comment: "")).font(.title3)) {
                    Text("Not implemented yet...").font(.footnote)
                    Picker("Push Server", selection: $pushServer) {
                        Text("Europe 1").tag(0)
                        Text("Europe 2").tag(1)
                    }.pickerStyle(.menu)//.menuStyle(.borderlessButton)
                }
            }
            .navigationBarHidden(true)
        }
        .navigationTitle(Text(NSLocalizedString("Notifications", comment: "")))
        .navigationViewStyle(.stack)
        .onAppear(perform: {
            UNUserNotificationCenter.current().getNotificationSettings { (settings) -> Void in
                self.pushPermissionEnabled = (settings.alertSetting == UNNotificationSetting.enabled);
            }
        });
    }

    init() {
        self.applePushEnabled = MLXMPPManager.sharedInstance().hasAPNSToken;
        self.applePushToken = MLXMPPManager.sharedInstance().pushToken;
        var xmppAccounts: [AccountPushInfo] = [];
        for entry in MLXMPPManager.sharedInstance().connectedXMPP {
            let xmppAccount = entry as! xmpp
            xmppAccounts.append(
                AccountPushInfo(accountName: xmppAccount.connectionProperties.identity.jid, pushEnabled: xmppAccount.connectionProperties.pushEnabled)
            )
        }
        self.xmppAccounts = xmppAccounts;
    }
}

struct PushSettings_Previews: PreviewProvider {
    static var previews: some View {
        NotificationSettings()
    }
}
