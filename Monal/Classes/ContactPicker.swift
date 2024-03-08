//
//  ContactList.swift
//  Monal
//
//  Created by Jan on 15.12.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

import SwiftUI
import monalxmpp
import OrderedCollections

struct ContactPickerEntry: View {
    let contact : ObservableKVOWrapper<MLContact>
    let isPicked: Bool
    let isExistingMember: Bool

    var body:some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .center) {
                if(isExistingMember) {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.gray)
                } else if(isPicked) {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.blue)
                } else {
                    Image(systemName: "circle")
                }
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

struct ContactPicker: View {
    @Environment(\.presentationMode) private var presentationMode

    @State var contacts: OrderedSet<ObservableKVOWrapper<MLContact>>
    let account: xmpp
    @Binding var selectedContacts: OrderedSet<ObservableKVOWrapper<MLContact>>
    let existingMembers: OrderedSet<ObservableKVOWrapper<MLContact>>
    @State var searchText = ""

    @State var isEditingSearchInput: Bool = false

    init(account: xmpp, selectedContacts: Binding<OrderedSet<ObservableKVOWrapper<MLContact>>>) {
        self.init(account: account, selectedContacts: selectedContacts, existingMembers: OrderedSet())
    }

    init(account: xmpp, selectedContacts: Binding<OrderedSet<ObservableKVOWrapper<MLContact>>>, existingMembers: OrderedSet<ObservableKVOWrapper<MLContact>>) {
        self.account = account
        self._selectedContacts = selectedContacts
        self.existingMembers = existingMembers

        var contactsTmp: OrderedSet<ObservableKVOWrapper<MLContact>> = OrderedSet()
        for contact in DataLayer.sharedInstance().possibleGroupMembers(forAccount: account.accountNo) {
            contactsTmp.append(ObservableKVOWrapper(contact))
        }
        _contacts = State(wrappedValue: contactsTmp)
    }

    private var searchResults : OrderedSet<ObservableKVOWrapper<MLContact>> {
        if searchText.isEmpty {
            return self.contacts
        } else {
            var filteredContacts: OrderedSet<ObservableKVOWrapper<MLContact>> = OrderedSet()
            for contact in self.contacts {
                if (contact.contactDisplayName as String).lowercased().contains(searchText.lowercased()) ||
                    (contact.contactJid as String).contains(searchText.lowercased()) {
                    filteredContacts.append(contact)
                }
            }
            return filteredContacts
        }
    }

    var body: some View {
        if(contacts.isEmpty) {
            Text("No contacts to show :(")
                .navigationTitle("Contact Lists")
        } else {
            List {
                ForEach(searchResults, id: \.self.obj) { contact in
                    let contactIsSelected = self.selectedContacts.contains(contact);
                    let contactIsAlreadyMember = self.existingMembers.contains(contact);
                    ContactPickerEntry(contact: contact, isPicked: contactIsSelected, isExistingMember: contactIsAlreadyMember)
                    .onTapGesture(perform: {
                        // only allow changes to members that are not already part of the group
                        if(!contactIsAlreadyMember) {
                            if(contactIsSelected) {
                                self.selectedContacts.remove(contact)
                            } else {
                                self.selectedContacts.append(contact)
                            }
                        }
                    })
                }
            }
            .applyClosure { view in
                if #available(iOS 15.0, *) {
                    view.searchable(text: $searchText, placement: .automatic, prompt: nil)
                } else {
                    view
                }
            }
            .listStyle(.inset)
            .navigationBarTitle("Contact Selection", displayMode: .inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back", action: {
                        self.presentationMode.wrappedValue.dismiss()
                    })
                }
            }
        }
    }
}
