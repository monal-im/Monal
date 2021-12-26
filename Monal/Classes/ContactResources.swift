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

func resourceRowElement(k: String, v: String, space: CGFloat = 5) -> some View {
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
    private var contactVersionInfos: OrderedDictionary<String, MLContactSoftwareVersionInfo> = OrderedDictionary()

    init(contact: ObservableKVOWrapper<MLContact>, previewMockOpt: OrderedDictionary<String, MLContactSoftwareVersionInfo>? = nil) {
        _contact = StateObject(wrappedValue: contact)

        if let previewMock = previewMockOpt {
            self.contactVersionInfos = previewMock
        } else {
            let ressourceNames: Array<String> = DataLayer.sharedInstance().resources(for: contact.obj)
            for ressourceName in ressourceNames {
                // query software version
                MLXMPPManager.sharedInstance()
                    .getEntitySoftWareVersion(for: contact.obj, andResource: ressourceName)

                let softwareInfoOpt: MLContactSoftwareVersionInfo? = DataLayer.sharedInstance().getSoftwareVersionInfo(forContact: contact.obj.contactJid, resource: ressourceName, andAccount: contact.obj.accountId)
                if let softwareInfo = softwareInfoOpt {
                    self.contactVersionInfos[ressourceName] = softwareInfo
                }
            }
        }
    }

    var body: some View {
        VStack {
            ForEach(self.contactVersionInfos.keys, id: \.self) { resourceKey in
                if let versionInfo = self.contactVersionInfos[resourceKey] {
                    VStack {
                        resourceRowElement(k: "Resource:", v: versionInfo.resource)
                        resourceRowElement(k: "Client Name:", v: versionInfo.appName)
                        resourceRowElement(k: "Client Version:", v: versionInfo.appVersion)
                        resourceRowElement(k: "OS:", v: versionInfo.platformOs)
                    }
                    Spacer().frame(height: 30)
                }
            }
            Spacer()
        }
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
