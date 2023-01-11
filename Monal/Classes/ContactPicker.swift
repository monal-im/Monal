//
//  ContactList.swift
//  Monal
//
//  Created by Jan on 15.12.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

import SwiftUI
import monalxmpp

struct ContactEntry: View { // TODO move
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

struct ContactPickerEntry: View {
    let contact : MLContact

    @Binding var selectedByIndex : [Bool]
    let idx : Int

    var body:some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .center) {
                if(self.selectedByIndex[idx]) {
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
        .onTapGesture(perform: {
            self.selectedByIndex[idx] = !self.selectedByIndex[idx]
        })
    }
}

struct ContactPicker: View {
    @Environment(\.presentationMode) private var presentationMode

    private let selectedContactsCallback : ([MLContact]) -> Void

    let contacts : [MLContact]
    let selectedContacts : [MLContact] // already selected when going into the view
    @State var selectedByIndex : [Bool] = []
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
                ForEach(Array(contacts.enumerated()), id: \.element) { idx, contact in
                    if matchesSearch(contact: contact) {
                        ContactPickerEntry(contact: contact, selectedByIndex: $selectedByIndex, idx: idx)
                    }
                }
            }
            .listStyle(.inset)
            .navigationBarTitle("Contact Selection", displayMode: .inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back", action: {
                        var selectedContacts : [MLContact] = []
                        for (idx, selected) in self.selectedByIndex.enumerated() {
                            if(selected) {
                                selectedContacts.append(self.contacts[idx])
                            }
                        }
                        self.selectedContactsCallback(selectedContacts)
                        self.presentationMode.wrappedValue.dismiss()
                    })
                }
            }.onAppear(perform: {
                self.selectedByIndex = [Bool].init(repeating: false, count: self.contacts.count)
                for (idx, contact) in contacts.enumerated() {
                    var isSelected = false
                    for selected in self.selectedContacts {
                        if(contact.contactJid == selected.contactJid) {
                            isSelected = true
                            break;
                        }
                    }
                    if(isSelected) {
                        self.selectedByIndex[idx] = true
                    }
                }
            })
        }
    }

    init(excludedContacts: [ObservableKVOWrapper<MLContact>], selectedContacts: [MLContact], selectedContactsCallback: @escaping ([MLContact]) -> Void) {
        self.selectedContacts = selectedContacts
        self.selectedContactsCallback = selectedContactsCallback
        let allContacts = DataLayer.sharedInstance().contactList() as! [MLContact]
        if excludedContacts.isEmpty {
            self.contacts = allContacts
        } else {
            var withoutExcluded : [MLContact] = []
            for contact in allContacts {
                var isExcluded = false
                for excluded in excludedContacts {
                    if(contact.contactJid == excluded.obj.contactJid) {
                        isExcluded = true
                        break;
                    }
                }
                if(!isExcluded) {
                    withoutExcluded.append(contact);
                }
            }
            self.contacts = withoutExcluded
        }
    }
}

struct ContactList_Previews: PreviewProvider {
    static var previews: some View {
        ContactPicker(excludedContacts: [], selectedContacts: [], selectedContactsCallback: { contacts in
        })
    }
}
