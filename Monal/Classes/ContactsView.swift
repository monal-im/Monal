//
//  ContactsView.swift
//  Monal
//
//  Created by Matthew Fennell <matthew@fennell.dev> on 10/08/2024.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import SwiftUI

struct ContactViewEntry: View {
    private let contact: MLContact
    @Binding private var selectedContactForContactDetails: ObservableKVOWrapper<MLContact>?
    private let dismissWithContact: (MLContact) -> ()

    @State private var shouldPresentRemoveContactAlert: Bool = false

    private var removeContactButtonText: String {
        if (!isDeletable) {
            return "Cannot delete notes to self"
        }
        return contact.isMuc ? "Remove Conversation" : "Remove Contact"
    }

    private var removeContactConfirmationTitle: String {
        contact.isMuc ? "Leave this converstion?" : "Remove \(contact.contactJid) from contacts?"
    }

    private var removeContactConfirmationDetail: String {
        contact.isMuc ? "" : "They will no longer see when you are online. They may not be able to access your encryption keys."
    }

    private var isDeletable: Bool {
        !contact.isSelfChat
    }

    init (contact: MLContact, selectedContactForContactDetails: Binding<ObservableKVOWrapper<MLContact>?>, dismissWithContact: @escaping (MLContact) -> ()) {
        self.contact = contact
        self._selectedContactForContactDetails = selectedContactForContactDetails
        self.dismissWithContact = dismissWithContact
    }

    var body: some View {
        // Apple's list dividers only extend as far left as the left-most text in the view.
        // This means, by default, that the dividers on this screen would not extend all the way to the left of the view.
        // This combination of HStack with spacing of 0, and empty text at the left of the view, is a workaround to override this behaviour.
        // See https://stackoverflow.com/a/76698909
        HStack(spacing: 0) {
            Text("").frame(maxWidth: 0)
            Button(action: { dismissWithContact(contact) }) {
                HStack {
                    ContactEntry(contact: ObservableKVOWrapper<MLContact>(contact))
                    Spacer()
                    Button {
                        selectedContactForContactDetails = ObservableKVOWrapper<MLContact>(contact)
                    } label: {
                        Image(systemName: "info.circle")
                            .imageScale(.large)
                    }
                    .accessibilityLabel("Open contact details")
                }
            }
        }
        .swipeActions(allowsFullSwipe: false) {
            // We do not use a Button with destructive role here as we would like to display the confirmation dialog first.
            // A destructive role would dismiss the row immediately, without waiting for the confirmation.
            Button(removeContactButtonText) {
                shouldPresentRemoveContactAlert = true
            }
            .tint(isDeletable ? .red : .gray)
            .disabled(!isDeletable)
        }
        .confirmationDialog(removeContactConfirmationTitle, isPresented: $shouldPresentRemoveContactAlert, titleVisibility: .visible) {
            Button(role: .cancel) {} label: {
                Text("No")
            }
            Button(role: .destructive) {
                MLXMPPManager.sharedInstance().remove(contact)
            } label: {
                Text("Yes")
            }
        } message: {
            Text(removeContactConfirmationDetail)
        }
    }
}

struct ContactsView: View {
    @ObservedObject private var contacts: Contacts
    private let delegate: SheetDismisserProtocol
    private let dismissWithContact: (MLContact) -> ()

    @State private var searchText: String = ""
    @State private var selectedContactForContactDetails: ObservableKVOWrapper<MLContact>? = nil

    init(contacts: Contacts, delegate: SheetDismisserProtocol, dismissWithContact: @escaping (MLContact) -> ()) {
        self.contacts = contacts
        self.delegate = delegate
        self.dismissWithContact = dismissWithContact
    }

    private static func shouldDisplayContact(contact: MLContact) -> Bool {
#if IS_QUICKSY
        return true
#endif
        return contact.isSubscribedTo || contact.hasOutgoingContactRequest || contact.isSubscribedFrom
    }

    private var contactList: [MLContact] {
        return contacts.contacts
            .filter(ContactsView.shouldDisplayContact)
            .sorted { ContactsView.sortingCriteria($0) < ContactsView.sortingCriteria($1) }
    }

    private var searchResults: [MLContact] {
        if searchText.isEmpty { return contactList }
        return contactList.filter { searchMatchesContact(contact: $0, search: searchText) }
    }

    private static func sortingCriteria(_ contact: MLContact) -> (String, String) {
        return (contact.contactDisplayName.lowercased(), contact.contactJid.lowercased())
    }

    private func searchMatchesContact(contact: MLContact, search: String) -> Bool {
        let jid = contact.contactJid.lowercased()
        let name = contact.contactDisplayName.lowercased()
        let search = search.lowercased()

        return jid.contains(search) || name.contains(search)
    }

    var body: some View {
        List {
            ForEach(searchResults, id: \.self) { contact in
                ContactViewEntry(contact: contact, selectedContactForContactDetails: $selectedContactForContactDetails, dismissWithContact: dismissWithContact)
            }
        }
        .animation(.default, value: contactList)
        .navigationTitle(Text("Contacts"))
        .listStyle(.plain)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .keyboardType(.emailAddress)
        .overlay {
            if contactList.isEmpty {
                ContentUnavailableShimView("You need friends for this ride", systemImage: "figure.wave", description: Text("Add new contacts with the + button above. Your friends will pop up here when they can talk"))
            } else if searchResults.isEmpty {
                ContentUnavailableShimView.search
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(destination: CreateGroupMenu(delegate: SheetDismisserProtocol())) {
                    Image(systemName: "person.3.fill")
                }
                .accessibilityLabel("Create contact group")

                NavigationLink(destination: AddContactMenu(delegate: SheetDismisserProtocol(), dismissWithNewContact: dismissWithContact)) {
                    Image(systemName: "person.fill.badge.plus")
                        .overlay { NumberlessBadge($contacts.requestCount) }
                }
                .accessibilityLabel(contacts.requestCount > 0 ? "Add contact (contact requests pending)" : "Add New Contact")
            }
        }
        .sheet(item: $selectedContactForContactDetails) { selectedContact in
            AnyView(AddTopLevelNavigation(withDelegate: delegate, to: ContactDetails(delegate:delegate, contact:selectedContact)))
        }
    }
}

class Contacts: ObservableObject {
    @Published var contacts: Set<MLContact>
    @Published var requestCount: Int
    private var subscriptions: Set<AnyCancellable> = Set()

    init() {
        self.contacts = Set(DataLayer.sharedInstance().contactList())
        self.requestCount = DataLayer.sharedInstance().allContactRequests().count
        subscriptions = [
            NotificationCenter.default.publisher(for: NSNotification.Name("kMonalContactRemoved"))
                .receive(on: DispatchQueue.main)
                .sink() { _ in self.refreshContacts() },
            NotificationCenter.default.publisher(for: NSNotification.Name("kMonalContactRefresh"))
                .receive(on: DispatchQueue.main)
                .sink() { _ in self.refreshContacts() }
        ]
    }

    private func refreshContacts() {
        self.contacts = Set(DataLayer.sharedInstance().contactList())
        self.requestCount = DataLayer.sharedInstance().allContactRequests().count
    }
}
