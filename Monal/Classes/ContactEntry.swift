//
//  ContactEntry.swift
//  Monal
//
//  Created by Friedrich Altheide on 28.11.23.
//  Copyright © 2023 monal-im.org. All rights reserved.
//

import SwiftUI

struct ContactEntry: View {
    let contact : MLContact

    var body:some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .center) {
                Image(uiImage: contact.avatar)
                    .resizable()
                    .frame(width: 40, height: 40, alignment: .center)
                VStack(alignment: .leading) {
                    Text(contact.contactDisplayName as String)
                    Text(contact.contactJid as String).font(.footnote).opacity(0.6)
                }
            }
        }
    }
}

#Preview {
    ContactEntry(contact:MLContact.makeDummyContact(0))
}

#Preview {
    ContactEntry(contact:MLContact.makeDummyContact(1))
}

#Preview {
    ContactEntry(contact:MLContact.makeDummyContact(2))
}

#Preview {
    ContactEntry(contact:MLContact.makeDummyContact(3))
}
