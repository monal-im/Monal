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

func resourceRowElement(_ k: String, _ v: String, space: CGFloat = 5) -> some View {
    HStack {
        Text(k)
        Spacer()
            .frame(width: space)
        Text(v)
        Spacer()
    }
}

struct ContactResources: View {
    @StateObject var contact: ObservableKVOWrapper<MLContact>
    @State var contactVersionInfos: OrderedDictionary<String, MLContactSoftwareVersionInfo>
    
    init(contact: ObservableKVOWrapper<MLContact>, previewMockOpt: OrderedDictionary<String, MLContactSoftwareVersionInfo>? = nil) {
        _contact = StateObject(wrappedValue: contact)

        if let previewMock = previewMockOpt {
            self.contactVersionInfos = previewMock
        } else {
            self.contactVersionInfos = OrderedDictionary()
            for ressourceName in DataLayer.sharedInstance().resources(for: contact.obj) {
                // query software version from contact
                MLXMPPManager.sharedInstance()
                    .getEntitySoftWareVersion(for: contact.obj, andResource: ressourceName)

                // load already known software version info from database
                if let softwareInfo = DataLayer.sharedInstance().getSoftwareVersionInfo(forContact: contact.obj.contactJid, resource: ressourceName, andAccount: contact.obj.accountId) {
                    self.contactVersionInfos[ressourceName] = softwareInfo
                }
            }
        }
    }

    var body: some View {
        ScrollView {
            List {
                ForEach(self.contactVersionInfos.keys, id: \.self) { resourceKey in
                    if let versionInfo = self.contactVersionInfos[resourceKey] {
                        VStack {
                            resourceRowElement("Resource:", versionInfo.resource)
                            resourceRowElement("Client Name:", versionInfo.appName)
                            resourceRowElement("Client Version:", versionInfo.appVersion)
                            resourceRowElement("OS:", versionInfo.platformOs)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalXmppUserSoftWareVersionRefresh"))) { notification in
                    if let userInfo = notification.userInfo, let softwareInfo = userInfo["versionInfo"] as? MLContactSoftwareVersionInfo {
                        self.contactVersionInfos[softwareInfo.resource] = softwareInfo
                    }
                }
            }
            Spacer()
        }
        //.navigationBarTitle(String(format: NSLocalizedString("Clients of %@", comment: ""), contact.contactDisplayName))
        .navigationBarTitle("Clients")
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
        ContactResources(contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(0)), previewMockOpt: previewMock())
    }
}
