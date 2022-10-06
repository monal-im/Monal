//
//  NotificationSettings.swift
//  Monal
//
//  Created by Jan on 02.05.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import SwiftUI
import monalxmpp
import OrderedCollections

struct AddContactsNewMenu: View {
    var delegate: SheetDismisserProtocol
    @State private var usedAccount: String = "1@jid"
    @State private var toAdd: String = ""

    var body: some View {
        Form {
            Section(header: Text("Contact and Channel Jids  are usually in the format: name@domain.tld")) {
                Picker("Use account", selection: $usedAccount) {
                    Text("1@jid").tag("1@jid")
                    Text("2@jid").tag("2@jid")
                }
                .pickerStyle(.menu)
                TextField("Contact or Channel-JID", text: $toAdd)
            }
            Section {
                Button(action: {
                    // TODO
                }, label: {
                    Text("Add Channel or Contact")
                })
            }
        }
        .navigationTitle("Add Contact or Channel")
        .toolbar(content: {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    // TODO
                }, label: {
                    Image(systemName: "camera")
                })
            }
        })
    }

    init(delegate: SheetDismisserProtocol) {
        self.delegate = delegate
    }
}

struct AddContactsRequestMenu: View {
    var delegate: SheetDismisserProtocol

    var body: some View {
        List {
            Section(header: Text("Allowing someone to add you as a contact lets them see when you are online. It also allows you to send encrypted messages.  Tap to approve. Swipe to reject.")) {
                Text("TODO")
            }
        }
        .navigationTitle("Contact Requests")
    }

    init(delegate: SheetDismisserProtocol) {
        self.delegate = delegate
    }
}

struct AddContactsMainMenu: View {
    var delegate: SheetDismisserProtocol

    var body: some View {
        NavigationView {
            List {
                Group {
                    NavigationLink(destination: LazyClosureView(AddContactsNewMenu(delegate: self.delegate))) {
                        Text("Add new Contact or Channel")
                    }
                    NavigationLink(destination: LazyClosureView(AddContactsRequestMenu(delegate: self.delegate))) {
                        Text("View Contact Requests")
                    }
                }
                .foregroundColor(.primary)
            }
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarLeading, content: {
                    Button(action: {
                        self.delegate.dismiss()
                    }, label: {
                        Text("Close")
                    })
                    .foregroundColor(monalGreen)
                    // TODO monalGreen for back buttons
                })
            })
        }
    }

    init(delegate: SheetDismisserProtocol) {
        self.delegate = delegate
    }
}

struct AddContacts_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        AddContactsNewMenu(delegate:delegate)
        AddContactsRequestMenu(delegate:delegate)
        AddContactsMainMenu(delegate:delegate)
    }
}
