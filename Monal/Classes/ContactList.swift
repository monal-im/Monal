//
//  ContactList.swift
//  Monal
//
//  Created by Jan on 15.12.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

import SwiftUI
import monalxmpp

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

struct ContactList: View {
    @State var contacts : [MLContact]
    @State var selectedContact : MLContact?
    @State var searchFieldInput = ""

    func matchesSearch(contact : MLContact) -> Bool {
        // TODO better lookup
        if searchFieldInput.isEmpty == true {
            return true
        } else {
            return contact.contactDisplayName.lowercased().contains(searchFieldInput.lowercased()) ||
                contact.contactJid.contains(searchFieldInput.lowercased())
        }
    }

    var body: some View {
        if(contacts.isEmpty) {
            Text("No contacts to show :(")
                .navigationTitle("Contact Lists")
        } else {
            List {
                Section {
                    TextField("Search contacts", text: $searchFieldInput)
                }
                ForEach(contacts, id: \.self) { contact in
                    if matchesSearch(contact: contact) {
                        ContactEntry(contact: contact)
                    }
                }
                .onDelete {
                    print(contacts.remove(atOffsets: $0))
                }
                .onInsert(of: [""], perform: { _,_ in
                })
            }
            .listStyle(.inset)
            .navigationBarTitle("Contact List", displayMode: .inline)
            .toolbar {
                EditButton()
            }
        }
    }
}

struct ContactList_Previews: PreviewProvider {
    static var previews: some View {
        ContactList(contacts: [
            MLContact.makeDummyContact(0),
            MLContact.makeDummyContact(1),
            MLContact.makeDummyContact(2),
            MLContact.makeDummyContact(3)]
        )
    }
}
