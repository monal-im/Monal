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
    // var contact: MLContact
    var contact : MLContact = MLContact()

    init(withContact: MLContact) {
            // UITableView.appearance().separatorColor = .none
            //UITableView.appearance().separatorColor = .clear
        self.contact = withContact
    }

    var body: some View {
        VStack {
            Text(contact.fullName)
            Image("noicon_muc")
                .resizable()
                .frame(minWidth: 100, idealWidth: 200, maxWidth: 300, minHeight: 100, idealHeight: 200, maxHeight: 300, alignment: .center)
                .scaledToFit()
            Text(contact.contactJid)
            if(!contact.isGroup) {
                Text("Zuletzt gesehen: \(contact.lastInteractionTime)")
            }
            HStack {
                Spacer()
                Image(systemName: "moon")
                Spacer().frame(width: 20)
                Image(systemName: "phone")
                Spacer().frame(width: 20)
                Image(systemName: "lock")
                Spacer()
            }
        }
    }
}

struct ContactDetailsHeader_Previews: PreviewProvider {
    static var previews: some View {
        ContactDetailsHeader(withContact: MLContact.makeDummyContact(0))
        ContactDetailsHeader(withContact: MLContact.makeDummyContact(1))
        ContactDetailsHeader(withContact: MLContact.makeDummyContact(2))
        ContactDetailsHeader(withContact: MLContact.makeDummyContact(3))
        ContactDetailsHeader(withContact: MLContact.makeDummyContact(4))
    }
}
