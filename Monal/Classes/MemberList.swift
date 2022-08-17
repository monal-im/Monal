//
//  MemberList.swift
//  Monal
//
//  Created by Jan on 28.05.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import SwiftUI
import monalxmpp

struct MemberList: View {
    private let memberList: [ObservableKVOWrapper<MLContact>]
    private let groupName: String
    private let account: xmpp?

    var body: some View {
        List {
            Section(header: Text(self.groupName)) {
                ForEach(self.memberList, id: \.self.obj) { contact in
                    NavigationLink(destination: LazyClosureView(ContactDetails(delegate: SheetDismisserProtocol(), contact: contact)), label: {
                        ZStack(alignment: .topLeading) {
                            HStack(alignment: .center) {
                                Image(uiImage: contact.obj.avatar)
                                    .resizable()
                                    .frame(width: 40, height: 40, alignment: .center)
                                Text(contact.contactDisplayName as String)
                            }
                            /*Button(action: {
                            }, label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                            })
                            .buttonStyle(.borderless)
                            .offset(x: -7, y: -7)*/
                        }
                    })
                }
            }
        }
        .navigationBarTitle("Group Members", displayMode: .inline)
        /*.toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack{
                    Button(action: {
                    }, label: {
                        Image(systemName: "person.fill.badge.plus")
                    })
                }
            }
        }*/
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
    }
}

struct MemberList_Previews: PreviewProvider {
    static var previews: some View {
        // TODO some dummy views, requires a dummy xmpp obj
        MemberList(mucContact: nil);
    }
}
