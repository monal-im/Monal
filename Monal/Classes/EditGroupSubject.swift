//
//  EditGroupSubject.swift
//  Monal
//
//  Created by Friedrich Altheide on 27.02.24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

struct EditGroupSubject: View {
    @StateObject var contact: ObservableKVOWrapper<MLContact>
    private let account: xmpp?
    @State private var subject: String

    @Environment(\.dismiss) var dismiss
    //@Environment(\.dismiss) var dismiss

    init(contact: ObservableKVOWrapper<MLContact>) {
        MLAssert(contact.isMuc, "contact must be a muc")
        
        _subject = State(wrappedValue: contact.obj.groupSubject)
        _contact = StateObject(wrappedValue: contact)
        self.account = contact.obj.account! as xmpp
    }

    var body: some View {
        NavigationStack {
            VStack {
                Form {
                    Section(header: Text("Group Description (optional)")) {
                        TextEditor(text: $subject)
                            .multilineTextAlignment(.leading)
                            .lineLimit(10...50)
                    }
                }
            }
            .navigationTitle(Text("Group/Channel description"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abort") {
                        self.dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        self.account!.mucProcessor.changeSubject(ofMuc: contact.contactJid, to: self.subject)
                        self.dismiss()
                    }
                }
            }
        }
    }
}
