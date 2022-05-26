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
    @State var contactVersionInfos: OrderedDictionary<String, MLContactSoftwareVersionInfo>

    init(contact: ObservableKVOWrapper<MLContact>, previewMock: OrderedDictionary<String, MLContactSoftwareVersionInfo>? = nil) {
        _contact = StateObject(wrappedValue: contact)
        
        if previewMock != nil {
            self.contactVersionInfos = previewMock!
        } else {
            var tmpInfos = OrderedDictionary<String, MLContactSoftwareVersionInfo>()
            for ressourceName in DataLayer.sharedInstance().resources(for: contact.obj) {
                // query software version from contact
                MLXMPPManager.sharedInstance()
                    .getEntitySoftWareVersion(for: contact.obj, andResource: ressourceName)

                // load already known software version info from database
                if let softwareInfo = DataLayer.sharedInstance().getSoftwareVersionInfo(forContact: contact.obj.contactJid, resource: ressourceName, andAccount: contact.obj.accountId) {
                    tmpInfos[ressourceName] = softwareInfo
                }
            }
            self.contactVersionInfos = tmpInfos
        }
    }

    var body: some View {
        List {
            ForEach(Array(self.contactVersionInfos.keys), id: \.self) { resourceKey in
                if let versionInfo = self.contactVersionInfos[resourceKey] {
                    Section {
                        resourceRowElement("Resource:", versionInfo.resource)
                        resourceRowElement("Client Name:", versionInfo.appName)
                        resourceRowElement("Client Version:", versionInfo.appVersion)
                        resourceRowElement("OS:", versionInfo.platformOs)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalXmppUserSoftWareVersionRefresh")).receive(on: RunLoop.main)) { notification in
                if let obj = notification.object as? xmpp, let softwareInfo = notification.userInfo?["versionInfo"] as? MLContactSoftwareVersionInfo {
                    if softwareInfo.fromJid == contact.obj.contactJid && obj.accountNo == contact.obj.accountId {
                        self.contactVersionInfos[softwareInfo.resource] = softwareInfo
                    }
                }
            }
        }
        .navigationBarTitle("Devices", displayMode: .inline)
    }
}

func previewMock() -> OrderedDictionary<String, MLContactSoftwareVersionInfo> {
    var previewMock: OrderedDictionary<String, MLContactSoftwareVersionInfo> = OrderedDictionary()
    previewMock["m1"] = MLContactSoftwareVersionInfo.init(jid: "test1@monal.im", andRessource: "m1", andAppName: "Monal", andAppVersion: "1.1.1", andPlatformOS: "ios")
    previewMock["m2"] = MLContactSoftwareVersionInfo.init(jid: "test1@monal.im", andRessource: "m2", andAppName: "Monal", andAppVersion: "1.1.2", andPlatformOS: "macOS")
    previewMock["m3"] = MLContactSoftwareVersionInfo.init(jid: "test1@monal.im", andRessource: "m3", andAppName: "Monal", andAppVersion: "1.1.2", andPlatformOS: "macOS")
    return previewMock
}

struct ContactResources_Previews: PreviewProvider {
    static var previews: some View {
        ContactResources(contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(0)), previewMock:previewMock())
    }
}
