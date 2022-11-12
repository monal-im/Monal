//
//  ContactRequestsMenu.swift
//  Monal
//
//  Created by Jan on 27.10.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

import SwiftUI
import monalxmpp

struct ContactRequestsMenuEntry: View {
    let contact : MLContact
    let doDelete: () -> ()
    @State private var isDeleted = false
    
    private func delete() {
        if(isDeleted == false) {
            isDeleted = true
            doDelete()
        }
    }

    var body: some View {
        HStack {
            Text(contact.contactJid)
            Spacer()
            Group {
                Button {
                    // deny request
                    MLXMPPManager.sharedInstance().reject(contact)
                    DataLayer.sharedInstance().deleteContactRequest(contact)
                    self.delete()
                } label: {
                    Image(systemName: "trash.circle")
                        .accentColor(.red)
                }
                Button {
                    // accept request
                    MLXMPPManager.sharedInstance().add(contact)
                    self.delete()
                } label: {
                    Image(systemName: "checkmark.circle")
                        .accentColor(.green)
                }
            }
            .font(.largeTitle)
        }
    }
}

struct ContactRequestsMenu: View {
    var delegate: SheetDismisserProtocol
    @State private var pendingRequests: [MLContact]

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Allowing someone to add you as a contact lets them see when you are online. It also allows you to send encrypted messages.")) {
                    if(pendingRequests.isEmpty) {
                        Text("No pending requests")
                            .foregroundColor(.secondary)
                    }
                    ForEach(pendingRequests.indices, id: \.self) { idx in
                        ContactRequestsMenuEntry(
                            contact: pendingRequests[idx],
                            doDelete: {
                                self.pendingRequests.remove(at: idx)
                        })
                    }
                }
            }
            
        }
        .navigationBarTitle("Contact Requests", displayMode: .inline)
        .navigationViewStyle(.stack)
    }

    init(delegate: SheetDismisserProtocol) {
        self.delegate = delegate
        self.pendingRequests = DataLayer.sharedInstance().contactRequestsForAccount() as! [MLContact]
    }
}

struct ContactRequestsMenu_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        ContactRequestsMenu(delegate: delegate)
    }
}
