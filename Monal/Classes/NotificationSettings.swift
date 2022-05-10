//
//  NotificationSettings.swift
//  Monal
//
//  Created by Jan on 02.05.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import SwiftUI
import monalxmpp

struct NotificationSettings: View {
    @ViewBuilder
    func buildLabel(_ description: Text, isWorking: Bool) -> some View {
        if(isWorking == true) {
            Label(title: {
                description
            }, icon: {
                Image(systemName: "checkmark.seal")
            }).accentColor(.green)
        } else {
            Label(title: {
                description
            }, icon: {
                Image(systemName: "xmark.seal")
            }).accentColor(.red)
        }
    }

    private let applePushEnabled: Bool
    private let applePushToken: String
    private let xmppAccountInfo: [xmpp]

    @State private var pushPermissionEnabled = false // state because we get this value through an async call
    @State private var showPushToken = false
    @State private var pushServer = 0

    var body: some View {
        NavigationView {
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
                Section(header: Text("Selected Region").font(.title3)) {
                    Text("Not implemented yet...").font(.footnote)
                    Picker("Push Server", selection: $pushServer) {
                        Text("Europe 1").tag(0)
                        Text("Europe 2").tag(1)
                    }.pickerStyle(.menu)//.menuStyle(.borderlessButton)
                }
            }
            // TODO fix those workarounds as soon as settings are not a storyboard anymore
            .navigationBarHidden(UIDevice.current.userInterfaceIdiom == .phone)
            .navigationBarTitle(Text("Notifications"), displayMode: .inline)
        }
        .navigationBarTitle(Text("Notifications"), displayMode: .inline)
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
        self.xmppAccountInfo = MLXMPPManager.sharedInstance().connectedXMPP as! [xmpp]
    }
}

struct PushSettings_Previews: PreviewProvider {
    static var previews: some View {
        NotificationSettings()
    }
}
