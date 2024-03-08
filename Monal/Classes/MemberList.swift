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
    private let account: xmpp
    private let ownAffiliation: String;
    @StateObject var group: ObservableKVOWrapper<MLContact>
    @State private var memberList: OrderedSet<ObservableKVOWrapper<MLContact>>
    @State private var affiliation: Dictionary<String, String>
    @State private var openAccountSelection : Bool = false
    @State private var showAlert = false
    @State private var alertPrompt = AlertPrompt(dismissLabel: Text("Close"))
    @State private var selectedMember: MLContact?

    init(mucContact: ObservableKVOWrapper<MLContact>) {
        self.account = MLXMPPManager.sharedInstance().getConnectedAccount(forID: mucContact.accountId)! as xmpp
        _group = StateObject(wrappedValue: mucContact)
        _memberList = State(wrappedValue: getContactList(viewContact: mucContact))
        self.ownAffiliation = DataLayer.sharedInstance().getOwnAffiliation(inGroupOrChannel:mucContact.obj) ?? "none"
        var affiliationTmp = Dictionary<String, String>()
        for memberInfo in Array(DataLayer.sharedInstance().getMembersAndParticipants(ofMuc: mucContact.contactJid, forAccountId: self.account.accountNo)) {
            guard let jid = memberInfo["participant_jid"] as? String ?? memberInfo["member_jid"] as? String else {
                continue
            }
            affiliationTmp.updateValue((memberInfo["affiliation"] as? String) ?? "none", forKey: jid)
        }
        _affiliation = State(wrappedValue: affiliationTmp)
    }

    func showAlert(title: String, description: String) {
        self.alertPrompt.title = Text(title)
        self.alertPrompt.message = Text(description)
        self.showAlert = true
    }

    func ownUserHasAffiliationToRemove(contact: ObservableKVOWrapper<MLContact>) -> Bool {
        if contact.obj.contactJid == self.account.connectionProperties.identity.jid {
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
        List {
            Section(header: Text(self.group.obj.contactDisplayName)) {
                if self.ownAffiliation == "owner" || self.ownAffiliation == "admin" {
                    NavigationLink(destination: LazyClosureView(ContactPicker(account: self.account, selectedContacts: $memberList, existingMembers: self.memberList)), label: {
                            Text("Add Group Members")
                    })
                }
                ForEach(self.memberList, id: \.self.obj) {
                    contact in
                    HStack(alignment: .center) {
                        Image(uiImage: contact.avatar)
                            .resizable()
                            .frame(width: 40, height: 40, alignment: .center)
                        Text(contact.contactDisplayName as String)
                        Spacer()
                        if let contactAffiliation = self.affiliation[contact.contactJid] {
                            if contactAffiliation == "owner" {
                                Text(NSLocalizedString("Owner", comment: "muc affiliation"))
                            } else if contactAffiliation == "admin" {
                                Text(NSLocalizedString("Admin", comment: "muc affiliation"))
                            } else if contactAffiliation == "member" {
                                Text(NSLocalizedString("Member", comment: "muc affiliation"))
                            } else if contactAffiliation == "outcast" {
                                Text(NSLocalizedString("Outcast", comment: "muc affiliation"))
                            } else {
                                Text(NSLocalizedString("<unknown>", comment: "muc affiliation"))
                            }
                        }
                    }
                    .onTapGesture(perform: {
                        if contact.obj.contactJid != self.account.connectionProperties.identity.jid {
                            self.selectedMember = contact.obj
                        }
                    })
                    .deleteDisabled(
                        !ownUserHasAffiliationToRemove(contact: contact)
                    )
                }
                .onDelete(perform: { memberIdx in
                    let member = self.memberList[memberIdx.first!]
                    self.account.mucProcessor.setAffiliation("none", ofUser: member.contactJid, inMuc: self.group.contactJid)

                    self.showAlert(title: "Member deleted", description: self.memberList[memberIdx.first!].contactJid)
                    self.memberList.remove(at: memberIdx.first!)
                })
            }
            .onChange(of: self.memberList) { [previousMemberList = self.memberList] newMemberList in
                // only handle new members (added via the contact picker)
                for member in newMemberList {
                    if !previousMemberList.contains(member) {
                        // add selected group member with affiliation member
                        affiliationChangeAction(member, affiliation: "member")
                    }
                }
            }
            .alert(isPresented: $showAlert, content: {
                Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton: .default(alertPrompt.dismissLabel))
            })
            .sheet(item: self.$selectedMember, content: { selectedMemberUnobserved in
                let selectedMember = ObservableKVOWrapper(selectedMemberUnobserved)
                VStack {
                    Form {
                        Section {
                            HStack {
                                Spacer()
                                Image(uiImage: selectedMember.avatar)
                                    .resizable()
                                    .frame(width: 150, height: 150, alignment: .center)
                                Spacer()
                            }
                            HStack {
                                Spacer()
                                Text(selectedMember.contactDisplayName as String)
                                Spacer()
                            }
                        }
                        Section(header: Text("Configure Membership")) {
                            if self.ownAffiliation == "owner" && self.affiliation[selectedMember.contactJid] == "owner" {
                                makeAdmin(selectedMember)
                                makeMember(selectedMember)
                                removeUserButton(selectedMember)
                                block(selectedMember)
                            }
                            if self.ownAffiliation == "owner" && self.affiliation[selectedMember.contactJid] == "admin" {
                                makeOwner(selectedMember)
                                makeMember(selectedMember)
                                removeUserButton(selectedMember)
                                block(selectedMember)
                            }
                            if self.ownAffiliation == "owner" && self.affiliation[selectedMember.contactJid] == "member" {
                                makeOwner(selectedMember)
                                makeAdmin(selectedMember)
                                removeUserButton(selectedMember)
                                block(selectedMember)
                            }
                            if self.ownAffiliation == "admin" && self.affiliation[selectedMember.contactJid] == "member" {
                                removeUserButton(selectedMember)
                                block(selectedMember)
                            }
                            if (self.ownAffiliation == "admin" || self.ownAffiliation == "owner") && self.affiliation[selectedMember.contactJid] == "outcast" {
                                makeMember(selectedMember)
                            }
                        }
                    }
                }
            })
        }
        .navigationBarTitle("Group Members", displayMode: .inline)
    }

    func removeUserButton(_ selectedMember: ObservableKVOWrapper<MLContact>) -> some View {
        if #available(iOS 15, *) {
            return Button(role: .destructive, action: {
                self.account.mucProcessor.setAffiliation("none", ofUser: selectedMember.contactJid, inMuc: self.group.contactJid)
                self.showAlert(title: "Member deleted", description: selectedMember.contactJid)
                if let index = self.memberList.firstIndex(of: selectedMember) {
                    self.memberList.remove(at: index)
                }
                self.selectedMember = nil
            }) {
                Text("Remove from group")
            }
        } else {
            return AnyView(EmptyView())
        }
    }

    func affiliationChangeAction(_ selectedMember: ObservableKVOWrapper<MLContact>, affiliation: String) {
        self.account.mucProcessor.setAffiliation(affiliation, ofUser: selectedMember.contactJid, inMuc: self.group.contactJid)
        self.affiliation[selectedMember.contactJid] = affiliation
    }

    func affiliationButton<Label: View>(_ selectedMember: ObservableKVOWrapper<MLContact>, affiliation: String, @ViewBuilder label: () -> Label) -> some View {
        return Button(action: {
            affiliationChangeAction(selectedMember, affiliation: affiliation)
            // dismiss sheet
            self.selectedMember = nil
        }) {
            label()
        }
    }

    func makeOwner(_ selectedMember: ObservableKVOWrapper<MLContact>) -> some View {
        return affiliationButton(selectedMember, affiliation: "owner", label: {
            Text("Make owner")
        })
    }

    func makeAdmin(_ selectedMember: ObservableKVOWrapper<MLContact>) -> some View {
        return affiliationButton(selectedMember, affiliation: "admin", label: {
            Text("Make admin")
        })
    }

    func makeMember(_ selectedMember: ObservableKVOWrapper<MLContact>) -> some View {
        return affiliationButton(selectedMember, affiliation: "member", label: {
            Text("Make member")
        })
    }

    func block(_ selectedMember: ObservableKVOWrapper<MLContact>) -> AnyView {
        if self.group.mucType != "group" {
            return AnyView(
                affiliationButton(selectedMember, affiliation: "outcast", label: {
                    Text("Block grom group")
                })
            )
        } else {
            return AnyView(EmptyView())
        }
    }
}

struct MemberList_Previews: PreviewProvider {
    static var previews: some View {
        MemberList(mucContact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(2)));
    }
}
