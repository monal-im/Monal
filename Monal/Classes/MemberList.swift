//
//  MemberList.swift
//  Monal
//
//  Created by Jan on 28.05.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import SwiftUI
import monalxmpp
import OrderedCollections

struct MemberList: View {
    @Environment(\.editMode) private var editMode

    private let memberList: [ObservableKVOWrapper<MLContact>]
    private let groupName: String
    private let account: xmpp?
    private let isAlpha: Bool

    @State private var openAccountSelection : Bool = false
    @State private var contactsToAdd : OrderedSet<MLContact> = []

    @State private var showAlert = false
    @State private var alertPrompt = AlertPrompt(dismissLabel: Text("Close"))
    func setAndShowAlert(title: String, description: String) {
        self.alertPrompt.title = Text(title)
        self.alertPrompt.message = Text(description)
        self.showAlert = true
    }

    var body: some View {
        // This is the invisible NavigationLink hack again...
        NavigationLink(destination:LazyClosureView(ContactPicker(selectedContacts: $contactsToAdd)), isActive: $openAccountSelection){}.hidden().disabled(true) // navigation happens as soon as our button sets navigateToQRCodeView to true...
        List {
            Section(header: Text(self.groupName)) {
                ForEach(self.memberList, id: \.self.obj) {
                    contact in
                    if contact.obj.contactJid != self.account?.connectionProperties.identity.jid {
                        NavigationLink(destination: LazyClosureView(ContactDetails(delegate: SheetDismisserProtocol(), contact: contact)), label: {
                            ZStack(alignment: .topLeading) {
                                HStack(alignment: .center) {
                                    Image(uiImage: contact.obj.avatar)
                                        .resizable()
                                        .frame(width: 40, height: 40, alignment: .center)
                                    Text(contact.contactDisplayName as String)
                                    if(editMode?.wrappedValue.isEditing == true) {
                                        Spacer()
                                        Button(action: {}, label: {
                                            Image(systemName: "slider.horizontal.3")
                                        })
                                    }
                                }
                            }
                        })
                    }
                }
                .onDelete(perform: { memberIdx in
                    // TODO maybe alert before deletion
                    if(memberIdx.count == 1) {
                        self.setAndShowAlert(title: "Member deleted", description: self.memberList[memberIdx.first!].contactJid)
                    }
                })
                .deleteDisabled(self.isAlpha)
            }.alert(isPresented: $showAlert, content: {
                Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton: .default(alertPrompt.dismissLabel))
            })
        }
        .toolbar {
            if(isAlpha && editMode?.wrappedValue.isEditing == true) {
                Button(action: {
                    openAccountSelection = true
                }, label: {
                    Image(systemName: "plus")
                        .foregroundColor(.blue)
                })
            }
            EditButton()
        }
        .navigationBarTitle("Group Members", displayMode: .inline)
    }

    init(mucContact: ObservableKVOWrapper<MLContact>?) {
        if let mucContact = mucContact {
            self.account = MLXMPPManager.sharedInstance().getConnectedAccount(forID: mucContact.obj.accountId)! as xmpp
            self.groupName = mucContact.contactDisplayName
            self.memberList = getContactList(viewContact: mucContact)
        } else {
            self.account = nil
            self.groupName = "Invalid Group"
            self.memberList = []
        }
#if IS_ALPA
        self.isAlpha = true
#else
        self.isAlpha = false
#endif
    }
}

struct MemberList_Previews: PreviewProvider {
    static var previews: some View {
        // TODO some dummy views, requires a dummy xmpp obj
        MemberList(mucContact: nil);
    }
}
