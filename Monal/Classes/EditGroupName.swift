//
//  EditGroupName.swift
//  Monal
//
//  Created by Friedrich Altheide on 24.02.24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import SwiftUI

@available(iOS 15.0, *)
struct EditGroupName: View {
    @ObservedObject var contact: ObservableKVOWrapper<MLContact>
    private let account: xmpp?

    @State private var groupName: String
    @State private var isEditingGroupName: Bool = false

    @Environment(\.dismiss) var dismiss

    init(contact: ObservableKVOWrapper<MLContact>) {
        MLAssert(contact.isGroup)

        _groupName = State(wrappedValue: contact.obj.contactDisplayName)
        self.contact = contact
        self.account = MLXMPPManager.sharedInstance().getConnectedAccount(forID: contact.accountId)! as xmpp
    }

    var body: some View {

        NavigationView {
                Form {
                    Section(header: Text("Group name")) {
                        TextField(NSLocalizedString("Group Name (optional)", comment: "placeholder when editing a group name"), text: $groupName, onEditingChanged: { isEditingGroupName = $0 })
                            .autocorrectionDisabled()
                            .autocapitalization(.none)
                            .addClearButton(isEditing: isEditingGroupName, text:$groupName)
                    }
                }
                .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abort") {
                        dismiss()
                    }
                }
                    ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        self.account!.mucProcessor.changeName(ofMuc: contact.contactJid, to: self.groupName)
                        dismiss()
                    }
                }
            }
        }
    }
}
