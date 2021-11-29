//
//  ContactDetailsHeader.swift
//  ContactDetailsHeader
//
//  Created by Friedrich Altheide on 03.09.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

import SwiftUI
import monalxmpp

struct ContactDetailsHeader: View {
    @StateObject var contact: ObservableKVOWrapper<MLContact>

    var body: some View {
        VStack {
            Image(uiImage: MLImageManager.sharedInstance().getIconFor(contact.obj)!)
                .resizable()
                .frame(minWidth: 50, idealWidth: 100, maxWidth: 200, minHeight: 50, idealHeight: 100, maxHeight: 200, alignment: .center)
                .scaledToFit()
            Spacer()
                .frame(height: 20)
            Text(contact.contactJid as String)
            Spacer()
                .frame(height: 20)
            if(contact.isGroup as Bool == false) {
                if((contact.lastInteractionTime as Date).timeIntervalSince1970 > 0) {
                    Text(String(format: NSLocalizedString("Last seen: %@", comment: ""),
                        DateFormatter.localizedString(from: contact.lastInteractionTime as Date, dateStyle: DateFormatter.Style.short, timeStyle: DateFormatter.Style.short)))
                } else {
                    Text(String(format: NSLocalizedString("Last seen: %@", comment: ""), NSLocalizedString("now", comment: "")))
                }
            }
            /*
            HStack {
                Spacer()
                Image(systemName: "moon")
                Spacer().frame(width: 20)
                Image(systemName: "phone")
                Spacer().frame(width: 20)
                Image(systemName: "lock")
                Spacer()
            }
            */
        }
    }
}

struct ContactDetailsHeader_Previews: PreviewProvider {
    static var previews: some View {
        ContactDetailsHeader(contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(0)))
        ContactDetailsHeader(contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(1)))
        ContactDetailsHeader(contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(2)))
        ContactDetailsHeader(contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(3)))
        ContactDetailsHeader(contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(4)))
    }
}
