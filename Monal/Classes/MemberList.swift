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
    @State private var memberList: [ObservableKVOWrapper<MLContact>]
    @State private var affiliation: Dictionary<String, String>
    @ObservedObject var group: ObservableKVOWrapper<MLContact>
    private let account: xmpp?
    private var ownAffiliation: String = "none";

    @State private var openAccountSelection : Bool = false
    @State private var contactsToAdd : OrderedSet<ObservableKVOWrapper<MLContact>> = []

    @State private var showAlert = false
    @State private var alertPrompt = AlertPrompt(dismissLabel: Text("Close"))

    init(mucContact: ObservableKVOWrapper<MLContact>?) {
        self.account = MLXMPPManager.sharedInstance().getConnectedAccount(forID: mucContact!.accountId)! as xmpp
        self.group = mucContact!;
        _memberList = State(wrappedValue: getContactList(viewContact: mucContact))
        var affiliationTmp = Dictionary<String, String>()
        for memberInfo in Array(DataLayer.sharedInstance().getMembersAndParticipants(ofMuc: mucContact!.contactJid, forAccountId: self.account!.accountNo)) {
            var jid : String? = memberInfo["participant_jid"] as? String
            if(jid == nil) {
                jid = memberInfo["member_jid"] as? String
            }
            if(jid == nil) {
                continue
            }
            if(jid == self.account?.connectionProperties.identity.jid) {
                self.ownAffiliation = memberInfo["affiliation"]! as! String
            }
            affiliationTmp.updateValue(memberInfo["affiliation"]! as! String, forKey: jid!)
        }
        _affiliation = State(wrappedValue: affiliationTmp)
    }

    func setAndShowAlert(title: String, description: String) {
        self.alertPrompt.title = Text(title)
        self.alertPrompt.message = Text(description)
        self.showAlert = true
    }

    func ownUserHasPermissionToRemove(contact: ObservableKVOWrapper<MLContact>) -> Bool {
        if contact.obj.contactJid == self.account?.connectionProperties.identity.jid {
            return false
        }
        if let contactAffiliation = self.affiliation[contact.contactJid] {
            if self.ownAffiliation == "owner" {
                return true
            } else if self.ownAffiliation == "admin" && contactAffiliation == "member" {
                return true
            }
        }
        return false
    }

    var body: some View {
        // This is the invisible NavigationLink hack again...
        NavigationLink(destination:LazyClosureView(ContactPicker(account: self.account!, selectedContacts: $contactsToAdd)), isActive: $openAccountSelection){}.hidden().disabled(true) // navigation happens as soon as our button sets navigateToQRCodeView to true...
        List {
            Section(header: Text(self.group.obj.contactDisplayName)) {
                ForEach(self.memberList, id: \.self.obj) {
                    contact in
                    NavigationLink(destination: LazyClosureView(ContactDetails(delegate: SheetDismisserProtocol(), contact: contact)), label: {
                        ZStack(alignment: .topLeading) {
                            HStack(alignment: .center) {
                                Image(uiImage: contact.avatar)
                                    .resizable()
                                    .frame(width: 40, height: 40, alignment: .center)
                                Text(contact.contactDisplayName as String)
                                Spacer()
                                if let contactAffiliation = self.affiliation[contact.contactJid] {
                                    if contactAffiliation == "owner" {
                                        Text(NSLocalizedString("Owner", comment: ""))
                                    } else if contactAffiliation == "admin" {
                                        Text(NSLocalizedString("Admin", comment: ""))
                                    } else if contactAffiliation == "member" {
                                        Text(NSLocalizedString("Member", comment: ""))
                                    } else if contactAffiliation == "outcast" {
                                        Text(NSLocalizedString("Outcast", comment: ""))
                                    } else {
                                        Text(NSLocalizedString("<unknown>", comment: ""))
                                    }
                                }
                            }
                        }
                    })
                    .deleteDisabled(
                        !ownUserHasPermissionToRemove(contact: contact)
                    )
                }
                .onDelete(perform: { memberIdx in
                    let member = self.memberList[memberIdx.first!]
                    self.account!.mucProcessor.setAffiliation("none", ofUser: member.contactJid, inMuc: self.group.contactJid)

                    self.setAndShowAlert(title: "Member deleted", description: self.memberList[memberIdx.first!].contactJid)
                    self.memberList.remove(at: memberIdx.first!)
                })
            }.alert(isPresented: $showAlert, content: {
                Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton: .default(alertPrompt.dismissLabel))
            })
        }
        .navigationBarTitle("Group Members", displayMode: .inline)
    }
}

struct MemberList_Previews: PreviewProvider {
    static var previews: some View {
        // TODO some dummy views, requires a dummy xmpp obj
        MemberList(mucContact: nil);
    }
}
