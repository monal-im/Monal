//
//  EditGroupSubject.swift
//  Monal
//
//  Created by Friedrich Altheide on 27.02.24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import SwiftUI

extension View {
    func versionConditionalLineLimit(_ limit: ClosedRange<Int>) -> some View {
        if #available(iOS 16.0, *) {
            return self.lineLimit(10...50)
        } else {
            return self
        }
    }
}

@available(iOS 15.0, *)
struct EditGroupSubject: View {
    @ObservedObject var contact: ObservableKVOWrapper<MLContact>
    private let account: xmpp?

    @State private var subject: String
    @State private var isEditingSubject: Bool = false

    @Environment(\.dismiss) var dismiss

    init(contact: ObservableKVOWrapper<MLContact>) {
        MLAssert(contact.isGroup)

        _subject = State(wrappedValue: contact.obj.groupSubject)
        self.contact = contact
        self.account = MLXMPPManager.sharedInstance().getConnectedAccount(forID: contact.accountId)! as xmpp
    }

    var body: some View {
        NavigationView {
            VStack {
                Form {
                    Section(header: Text("Group Description")) {
                        TextField(NSLocalizedString("Group Description (optional)", comment: "placeholder when editing a group description"), text: $subject, onEditingChanged: { isEditingSubject = $0 })
                            .multilineTextAlignment(.leading)
                            .versionConditionalLineLimit(10...50)
                            .addClearButton(isEditing: isEditingSubject, text:$subject)
                    }
                }
            }
            .navigationTitle("Group description")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abort") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        self.account!.mucProcessor.changeSubject(ofMuc: contact.contactJid, to: self.subject)
                        dismiss()
                    }
                }
            }
        }
    }
}
