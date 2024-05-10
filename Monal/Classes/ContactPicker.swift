//
//  ContactList.swift
//  Monal
//
//  Created by Jan on 15.12.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

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
                ContactEntry(contact: contact)
            }
        }
    }
}

struct ContactPicker: View {
    typealias completionType = (OrderedSet<ObservableKVOWrapper<MLContact>>)->Void
    let account: xmpp
    @Environment(\.presentationMode) private var presentationMode
    @Binding var returnedContacts: OrderedSet<ObservableKVOWrapper<MLContact>>
    @State var selectedContacts: OrderedSet<ObservableKVOWrapper<MLContact>>
    @State var searchText = ""
    @State var isEditingSearchInput = false
    let allowRemoval: Bool
    let completion: completionType?

    init(_ account: xmpp, initializeFrom contacts: OrderedSet<ObservableKVOWrapper<MLContact>>, allowRemoval: Bool = true, completion:completionType?) {
        self.account = account
        self.allowRemoval = allowRemoval
        self.completion = completion
        _selectedContacts = State(wrappedValue:OrderedSet())
        //use a temporary storage because we don't have a binding to the outside world but use the completion handler
        var storage = contacts
        _returnedContacts = Binding(
            get: { storage },
            set: { storage = $0 }
        )
        buildPreselectedContacts(contacts)
        DDLogError("self.allowRemoval = \(String(describing:self.allowRemoval))")
    }
    
    init(_ account: xmpp, binding returnedContacts: Binding<OrderedSet<ObservableKVOWrapper<MLContact>>>, allowRemoval: Bool = true) {
        self.account = account
        self.allowRemoval = allowRemoval
        self.completion = nil
        _selectedContacts = State(wrappedValue:OrderedSet())
        _returnedContacts = returnedContacts
        buildPreselectedContacts(returnedContacts.wrappedValue)
    }
    
    private mutating func buildPreselectedContacts(_ source: OrderedSet<ObservableKVOWrapper<MLContact>>) {
        //build currently selected list of contacts
        var contactsTmp: OrderedSet<ObservableKVOWrapper<MLContact>> = OrderedSet()
        for contact in source {
            contactsTmp.append(contact)
        }
        _selectedContacts = State(wrappedValue:contactsTmp)
    }
    
    private var allContacts: OrderedSet<ObservableKVOWrapper<MLContact>> {
        //build list of all possible contacts on this account (excluding selfchat and other mucs)
        var contactsTmp: OrderedSet<ObservableKVOWrapper<MLContact>> = OrderedSet()
        for contact in DataLayer.sharedInstance().possibleGroupMembers(forAccount: account.accountNo) {
            contactsTmp.append(ObservableKVOWrapper(contact))
        }
        return contactsTmp
    }

    private var searchResults : OrderedSet<ObservableKVOWrapper<MLContact>> {
        if searchText.isEmpty {
            return self.allContacts
        } else {
            var filteredContacts: OrderedSet<ObservableKVOWrapper<MLContact>> = OrderedSet()
            for contact in self.allContacts {
                if (contact.contactDisplayName as String).lowercased().contains(searchText.lowercased()) ||
                    (contact.contactJid as String).contains(searchText.lowercased()) {
                    filteredContacts.append(contact)
                }
            }
            return filteredContacts
        }
    }

    var body: some View {
        if(allContacts.isEmpty) {
            Text("No contacts to show :(")
                .navigationTitle("Contact Lists")
        } else {
            List(searchResults) { contact in
                let contactIsSelected = self.selectedContacts.contains(contact);
                let contactIsAlreadyMember = self.returnedContacts.contains(contact);
                ContactPickerEntry(contact: contact, isPicked: contactIsSelected, isExistingMember: !(!contactIsAlreadyMember || allowRemoval))
                    .onTapGesture {
                        // only allow changes to members that are not already part of the group
                        if(!contactIsAlreadyMember || allowRemoval) {
                            if(contactIsSelected) {
                                self.selectedContacts.remove(contact)
                            } else {
                                self.selectedContacts.append(contact)
                            }
                        }
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
            .navigationBarTitle(NSLocalizedString("Contact Selection", comment: ""), displayMode: .inline)
            .onDisappear {
                returnedContacts.removeAll()
                for contact in selectedContacts {
                    returnedContacts.append(contact)
                }
                if let completion = completion {
                    completion(returnedContacts)
                }
            }
        }
    }
}
