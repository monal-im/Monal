//
//  ContactResources.swift
//  Monal
//
//  Created by Friedrich Altheide on 24.12.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//
import monalxmpp

import SwiftUI
import OrderedCollections

@ViewBuilder
func resourceRowElement(_ k: String, _ v: String, space: CGFloat = 5) -> some View {
    HStack {
        Text(k).font(.headline)
        Spacer()
        Text(v).foregroundColor(.secondary)
    }
}

struct ContactResources: View {
    @StateObject var contact: ObservableKVOWrapper<MLContact>
    @State var contactVersionInfos: [String:ObservableKVOWrapper<MLContactSoftwareVersionInfo>]

    init(contact: ObservableKVOWrapper<MLContact>, previewMock: [String:ObservableKVOWrapper<MLContactSoftwareVersionInfo>]? = nil) {
        _contact = StateObject(wrappedValue: contact)
        
        if previewMock != nil {
            self.contactVersionInfos = previewMock!
        } else {
            var tmpInfos:[String:ObservableKVOWrapper<MLContactSoftwareVersionInfo>] = [:]
            for ressourceName in DataLayer.sharedInstance().resources(for: contact.obj) {
                // load already known software version info from database
                if let softwareInfo = DataLayer.sharedInstance().getSoftwareVersionInfo(forContact: contact.obj.contactJid, resource: ressourceName, andAccount: contact.obj.accountId) {
                    tmpInfos[ressourceName] = ObservableKVOWrapper<MLContactSoftwareVersionInfo>(softwareInfo)
                }
            }
            self.contactVersionInfos = tmpInfos
        }
    }

    var body: some View {
        List {
            ForEach(self.contactVersionInfos.sorted(by:{ $0.0 < $1.0 }), id: \.key) { key, value in
                if let versionInfo = value {
                    Section {
                        resourceRowElement("Resource:", versionInfo.resource ?? "")
                        resourceRowElement("Client Name:", versionInfo.appName ?? "")
                        resourceRowElement("Client Version:", versionInfo.appVersion ?? "")
                        resourceRowElement("OS:", versionInfo.platformOs ?? "")
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalXmppUserSoftWareVersionRefresh")).receive(on: RunLoop.main)) { notification in
            if let xmppAccount = notification.object as? xmpp, let softwareInfo = notification.userInfo?["versionInfo"] as? MLContactSoftwareVersionInfo {
                DDLogVerbose("Got software version info from account \(xmppAccount)...")
                if softwareInfo.fromJid == contact.obj.contactJid && xmppAccount.accountNo == contact.obj.accountId {
                    DispatchQueue.main.async {
                        DDLogVerbose("Successfully matched software version info update to current contact: \(contact.obj)")
                        self.contactVersionInfos[softwareInfo.resource] = ObservableKVOWrapper<MLContactSoftwareVersionInfo>(softwareInfo)
                    }
                }
            }
        }
        .onAppear {
            DDLogVerbose("View will appear...")
            let newTimeout = DispatchTime.now() + 1.0;
            DispatchQueue.main.asyncAfter(deadline: newTimeout) {
                DDLogVerbose("Refreshing software version info...")
                for ressourceName in DataLayer.sharedInstance().resources(for: contact.obj) {
                    // query software version from contact
                    MLXMPPManager.sharedInstance()
                        .getEntitySoftWareVersion(for: contact.obj, andResource: ressourceName)
                }
            }
        }
        .navigationBarTitle("Devices", displayMode: .inline)
    }
}

func previewMock() -> [String:ObservableKVOWrapper<MLContactSoftwareVersionInfo>] {
    var previewMock:[String:ObservableKVOWrapper<MLContactSoftwareVersionInfo>] = [:]
    previewMock["m1"] = ObservableKVOWrapper<MLContactSoftwareVersionInfo>(MLContactSoftwareVersionInfo.init(jid: "test1@monal.im", andRessource: "m1", andAppName: "Monal", andAppVersion: "1.1.1", andPlatformOS: "ios"))
    previewMock["m2"] = ObservableKVOWrapper<MLContactSoftwareVersionInfo>(MLContactSoftwareVersionInfo.init(jid: "test1@monal.im", andRessource: "m2", andAppName: "Monal", andAppVersion: "1.1.2", andPlatformOS: "macOS"))
    previewMock["m3"] = ObservableKVOWrapper<MLContactSoftwareVersionInfo>(MLContactSoftwareVersionInfo.init(jid: "test1@monal.im", andRessource: "m3", andAppName: "Monal", andAppVersion: "1.1.2", andPlatformOS: "macOS"))
    return previewMock
}

struct ContactResources_Previews: PreviewProvider {
    static var previews: some View {
        ContactResources(contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(0)), previewMock:previewMock())
    }
}
