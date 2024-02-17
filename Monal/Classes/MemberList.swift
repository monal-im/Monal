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

    @State private var memberList: [ObservableKVOWrapper<MLContact>]
    @ObservedObject var group: ObservableKVOWrapper<MLContact>
    private let account: xmpp?

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
        NavigationLink(destination:LazyClosureView(ContactPicker(account: self.account!, selectedContacts: $contactsToAdd)), isActive: $openAccountSelection){}.hidden().disabled(true) // navigation happens as soon as our button sets navigateToQRCodeView to true...
        List {
            Section(header: Text(self.group.obj.contactDisplayName)) {
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
                    let member = self.memberList[memberIdx.first!]
                    self.account!.mucProcessor.setAffiliation("none", ofUser: member.contactJid, inMuc: self.group.obj.contactJid)

                    self.setAndShowAlert(title: "Member deleted", description: self.memberList[memberIdx.first!].contactJid)
                    self.memberList.remove(at: memberIdx.first!)
                })
            }.alert(isPresented: $showAlert, content: {
                Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton: .default(alertPrompt.dismissLabel))
            })
        }
        .toolbar {
#if IS_ALPHA
            if(editMode?.wrappedValue.isEditing == true) {
                Button(action: {
                    openAccountSelection = true
                }, label: {
                    Image(systemName: "plus")
                        .foregroundColor(.blue)
                })
            }
#endif
            EditButton()
        }
        .navigationBarTitle("Group Members", displayMode: .inline)
    }

    init(mucContact: ObservableKVOWrapper<MLContact>?) {
        self.account = MLXMPPManager.sharedInstance().getConnectedAccount(forID: mucContact!.obj.accountId)! as xmpp
        self.group = mucContact!;
        _memberList = State(wrappedValue: getContactList(viewContact: mucContact))
    }
}

struct MemberList_Previews: PreviewProvider {
    static var previews: some View {
        // TODO some dummy views, requires a dummy xmpp obj
        MemberList(mucContact: nil);
    }
}
