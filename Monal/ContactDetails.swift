//
//  ContactDetails.swift
//  Monal
//
//  Created by Jan on 22.10.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//

import SwiftUI
import monalxmpp

struct ContactDetails: View {
    var contact : MLContact = MLContact()

    init(withContact: MLContact) {
            // UITableView.appearance().separatorColor = .none
            //UITableView.appearance().separatorColor = .clear
        self.contact = withContact
    }

    var body: some View {
        VStack {
            Spacer()
                .frame(height: 20)
            Text(contact.contactDisplayName())
            ContactDetailsHeader(withContact: contact)
            Spacer()
                .frame(height: 20)
            Text("Lorem impsum...")
            Spacer()
        }
    }
}

struct ContactDetails_Previews:
    PreviewProvider {
        static var previews: some View {
            ContactDetails(withContact: MLContact.makeDummyContact(0))
            ContactDetails(withContact: MLContact.makeDummyContact(1))
            ContactDetails(withContact: MLContact.makeDummyContact(2))
            ContactDetails(withContact: MLContact.makeDummyContact(3))
            ContactDetails(withContact: MLContact.makeDummyContact(4))
        }
    }

