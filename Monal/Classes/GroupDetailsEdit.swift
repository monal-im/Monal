//
//  GroupDetailsEdit.swift
//  Monal
//
//  Created by Friedrich Altheide on 23.02.24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import SwiftUI

struct GroupDetailsEdit: View {
    @ObservedObject var contact: ObservableKVOWrapper<MLContact>
    private let account: xmpp?

    @State private var showingSheet = false

    init(contact: ObservableKVOWrapper<MLContact>) {
        MLAssert(contact.isGroup)

        self.contact = contact
        self.account = MLXMPPManager.sharedInstance().getConnectedAccount(forID: contact.accountId)! as xmpp
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    Image(uiImage: contact.avatar)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel((contact.obj.mucType == "group") ? "Group Avatar" : "Channel Avatar")
                        .frame(width: 150, height: 150, alignment: .center)
                        .shadow(radius: 7)
                    Spacer()
                }
            }
            Section {
                if #available(iOS 15.0, *) {
                    Button(action: {
                        showingSheet.toggle()
                    }) {
                        HStack {
                            Image(systemName: "person.2")
                            Text(contact.contactDisplayName as String)
                            Spacer()
                        }
                    }
                    .sheet(isPresented: $showingSheet) {
                        LazyClosureView(EditGroupName(contact: contact))
                    }
                    Button(action: {
                        showingSheet.toggle()
                    }) {
                        HStack {
                            Image(systemName: "pencil")
                            Text((contact.obj.mucType == "group") ? "Group description" : "Channel description")
                            Spacer()
                        }
                    }
                    .sheet(isPresented: $showingSheet) {
                        LazyClosureView(EditGroupDescription(contact: contact))
                    }
                }
            }
        }
        .navigationTitle("Edit group")
    }
}

#Preview {
    GroupDetailsEdit(contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(0)))
}
