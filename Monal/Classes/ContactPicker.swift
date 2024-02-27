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

    var body:some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .center) {
                if(isPicked) {
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

    @State var contacts: [ObservableKVOWrapper<MLContact>]
    let account: xmpp
    @Binding var selectedContacts : OrderedSet<ObservableKVOWrapper<MLContact>> // already selected when going into the view
    @State var searchFieldInput = ""

    @State var isEditingSearchInput: Bool = false

    init(account: xmpp, selectedContacts: Binding<OrderedSet<ObservableKVOWrapper<MLContact>>>) {
        self.account = account
        self._selectedContacts = selectedContacts

        var contactsTmp: [ObservableKVOWrapper<MLContact>] = Array()
        for contact in DataLayer.sharedInstance().possibleGroupMembers(forAccount: account.accountNo) {
            contactsTmp.append(ObservableKVOWrapper(contact))
        }
        _contacts = State(wrappedValue: contactsTmp)
    }

    func matchesSearch(contact: ObservableKVOWrapper<MLContact>) -> Bool {
        // TODO better lookup
        if searchFieldInput.isEmpty == true {
            return true
        } else {
            return (contact.contactDisplayName as String).lowercased().contains(searchFieldInput.lowercased()) ||
                (contact.contactJid as String).contains(searchFieldInput.lowercased())
        }
    }

    var body: some View {
        if(contacts.isEmpty) {
            Text("No contacts to show :(")
                .navigationTitle("Contact Lists")
        } else {
            List {
                Section {
                    TextField(NSLocalizedString("Search contacts", comment: "placeholder in contact picker"), text: $searchFieldInput, onEditingChanged: { isEditingSearchInput = $0 })
                        .addClearButton(isEditing: isEditingSearchInput, text:$searchFieldInput)
                }
                ForEach(Array(contacts.enumerated()), id: \.element.obj.contactJid) { idx, contact in
                    if matchesSearch(contact: contact) {
                        let contactIsSelected = self.selectedContacts.contains(contact);
                        ContactPickerEntry(contact: contact, isPicked: contactIsSelected)
                        .onTapGesture(perform: {
                            if(contactIsSelected) {
                                self.selectedContacts.remove(contact)
                            } else {
                                self.selectedContacts.append(contact)
                            }
                        })
                    }
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
