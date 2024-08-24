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
        return contact.isGroup ? "Remove Conversation" : "Remove Contact"
    }

    private var removeContactConfirmationTitle: String {
        contact.isGroup ? "Leave this converstion?" : "Remove \(contact.contactJid) from contacts?"
    }

    private var removeContactConfirmationDetail: String {
        contact.isGroup ? "" : "They will no longer see when you are online. They may not be able to access your encryption keys."
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
                // The only purpose of this NavigationLink is making the button it contains look nice.
                // In other words: have a screen-wide touch target and the chveron on the right of the screen.
                // This avoids having to do manual button styling that might have to be recreated in the future.
                NavigationLink(destination: EmptyView()) {
                    HStack {
                        ContactEntry(contact: ObservableKVOWrapper<MLContact>(contact))
                        Spacer()
                        Button {
                            selectedContactForContactDetails = ObservableKVOWrapper<MLContact>(contact)
                        } label: {
                            Image(systemName: "info.circle")
                                .tint(.blue)
                                .imageScale(.large)
                        }
                        .accessibilityLabel("Open contact details")
                    }
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

    @State private var selectedContactForContactDetails: ObservableKVOWrapper<MLContact>? = nil

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

    private static func sortingCriteria(_ contact: MLContact) -> (String, String) {
        return (contact.contactDisplayName.lowercased(), contact.contactJid.lowercased())
    }

    init(contacts: Contacts, delegate: SheetDismisserProtocol, dismissWithContact: @escaping (MLContact) -> ()) {
        self.contacts = contacts
        self.delegate = delegate
        self.dismissWithContact = dismissWithContact
    }

    var body: some View {
        List {
            ForEach(contactList, id: \.self) { contact in
                ContactViewEntry(contact: contact, selectedContactForContactDetails: $selectedContactForContactDetails, dismissWithContact: dismissWithContact)
            }
        }
        .animation(.default, value: contactList)
        .navigationTitle("Contacts")
        .listStyle(.plain)
        .overlay {
            if contactList.isEmpty {
                ContentUnavailableShimView("You need friends for this ride", systemImage: "figure.wave", description: Text("Add new contacts with the + button above. Your friends will pop up here when they can talk"))
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(destination: CreateGroupMenu(delegate: SheetDismisserProtocol())) {
                    Image(systemName: "person.3.fill")
                }
                .accessibilityLabel("Create contact group")
                .tint(monalGreen)
                NavigationLink(destination: AddContactMenu(delegate: SheetDismisserProtocol(), dismissWithNewContact: dismissWithContact)) {
                    Image(systemName: "person.fill.badge.plus")
                        .overlay { NumberlessBadge($contacts.requestCount) }
                }
                .accessibilityLabel(contacts.requestCount > 0 ? "Add contact (contact requests pending)" : "Add New Contact")
                .tint(monalGreen)
            }
        }
        .sheet(item: $selectedContactForContactDetails) { selectedContact in
            AnyView(AddTopLevelNavigation(withDelegate: delegate, to: ContactDetails(delegate: SheetDismisserProtocol(), contact: selectedContact)))
        }
    }
}

class Contacts: ObservableObject {
    @Published var contacts: Set<MLContact>
    @Published var requestCount: Int

    init() {
        self.contacts = Set(DataLayer.sharedInstance().contactList())
        self.requestCount = DataLayer.sharedInstance().allContactRequests().count

        NotificationCenter.default.addObserver(self, selector: #selector(refreshContacts), name: NSNotification.Name("kMonalContactRemoved"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshContacts), name: NSNotification.Name("kMonalContactRefresh"), object: nil)
    }

    @objc
    private func refreshContacts() {
        self.contacts = Set(DataLayer.sharedInstance().contactList())
        self.requestCount = DataLayer.sharedInstance().allContactRequests().count
    }
}
