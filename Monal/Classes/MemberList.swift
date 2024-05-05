//
//  MemberList.swift
//  Monal
//
//  Created by Jan on 28.05.22.
//  Copyright © 2022 Monal.im. All rights reserved.
//

import OrderedCollections

struct ActionSheetPrompt {
    var title: Text = Text("")
    var message: Text = Text("")
    var closure: ()->Void = { }
}

struct MemberList: View {
    private let account: xmpp
    private let ownAffiliation: String;
    @StateObject var group: ObservableKVOWrapper<MLContact>
    @State private var memberList: OrderedSet<ObservableKVOWrapper<MLContact>>
    @State private var affiliations: Dictionary<ObservableKVOWrapper<MLContact>, String>
    @State private var navigationActive: ObservableKVOWrapper<MLContact>?
    @State private var showAlert = false
    @State private var alertPrompt = AlertPrompt(dismissLabel: Text("Close"))
    @State private var showActionSheet = false
    @State private var actionSheetPrompt = ActionSheetPrompt()

    init(mucContact: ObservableKVOWrapper<MLContact>) {
        account = MLXMPPManager.sharedInstance().getConnectedAccount(forID: mucContact.accountId)! as xmpp
        _group = StateObject(wrappedValue: mucContact)
        _memberList = State(wrappedValue: getContactList(viewContact: mucContact))
        ownAffiliation = DataLayer.sharedInstance().getOwnAffiliation(inGroupOrChannel:mucContact.obj) ?? "none"
        var affiliationTmp = Dictionary<ObservableKVOWrapper<MLContact>, String>()
        for memberInfo in Array(DataLayer.sharedInstance().getMembersAndParticipants(ofMuc: mucContact.contactJid, forAccountId: account.accountNo)) {
            guard let jid = memberInfo["participant_jid"] as? String ?? memberInfo["member_jid"] as? String else {
                continue
            }
            let contact = ObservableKVOWrapper(MLContact.createContact(fromJid:jid, andAccountNo:account.accountNo))
            affiliationTmp[contact] = memberInfo["affiliation"] as? String ?? "none"
        }
        _affiliations = State(wrappedValue: affiliationTmp)
    }

    func showAlert(title: Text, description: Text) {
        self.alertPrompt.title = title
        self.alertPrompt.message = description
        self.showAlert = true
    }
    
    func showActionSheet(title: Text, description: Text, closure: @escaping ()->Void) {
        self.actionSheetPrompt.title = title
        self.actionSheetPrompt.message = description
        self.actionSheetPrompt.closure = closure
        self.showActionSheet = true
    }

    func ownUserHasAffiliationToRemove(contact: ObservableKVOWrapper<MLContact>) -> Bool {
        if contact.contactJid == account.connectionProperties.identity.jid {
            return false
        }
        if let contactAffiliation = affiliations[contact] {
            if ownAffiliation == "owner" {
                return true
            } else if ownAffiliation == "admin" && (contactAffiliation != "owner" && contactAffiliation != "admin") {
                return true
            }
        }
        return false
    }
    
    func affiliationToText(_ affiliation: String?) -> some View {
        if let affiliation = affiliation {
            if affiliation == "owner" {
                return Text("Owner")
            } else if affiliation == "admin" {
                return Text("Admin")
            } else if affiliation == "member" {
                return Text("Member")
            } else if affiliation == "outcast" {
                return Text("Blocked")
            } else if affiliation == "profile" {
                return Text("Open contact details")
            }
        }
        return Text("<unknown>")
    }

    var body: some View {
        List {
            Section(header: Text(self.group.obj.contactDisplayName)) {
                if ownAffiliation == "owner" || ownAffiliation == "admin" {
                    NavigationLink(destination: LazyClosureView(ContactPicker(account, binding: $memberList, allowRemoval: false))) {
                        Text("Add Group Members")
                    }
                }
                ForEach(memberList, id:\.self) { contact in
                    if !contact.isSelfChat {
                        HStack(alignment: .center) {
                            ContactEntry(contact:contact)
                            
                            Spacer()
                            
                            if ownAffiliation == "owner" || ownAffiliation == "admin" {
                                Picker(selection: Binding<String>(
                                    get: { affiliations[contact] ?? "none" },
                                    set: { newAffiliation in
                                        if newAffiliation == "profile" {
                                            DDLogVerbose("Activating navigation to \(String(describing:contact))")
                                            navigationActive = contact
                                        } else if newAffiliation == "outcast" {
                                            showActionSheet(title: Text("Block user?"), description: Text("Do you want to block this user from entering this group/channel?")) {
                                                DDLogVerbose("Changing affiliation of \(String(describing:contact)) to: \(String(describing:newAffiliation))...")
                                                affiliations[contact] = newAffiliation
                                                account.mucProcessor.setAffiliation(newAffiliation, ofUser:contact.contactJid, inMuc:self.group.contactJid)
                                            }
                                        } else {
                                            DDLogVerbose("Changing affiliation of \(String(describing:contact)) to: \(String(describing:newAffiliation))...")
                                            affiliations[contact] = newAffiliation
                                            account.mucProcessor.setAffiliation(newAffiliation, ofUser:contact.contactJid, inMuc:self.group.contactJid)
                                        }
                                    }
                                ), label: EmptyView()) {
                                    ForEach(["profile", "owner", "admin", "member", "outcast"], id:\.self) { affiliation in
                                        affiliationToText(affiliation).tag(affiliation)
                                    }
                                }
                                .pickerStyle(.menu)
                            } else {
                                affiliationToText(affiliations[contact])
                            }
                        }
                        .deleteDisabled(
                            !ownUserHasAffiliationToRemove(contact: contact)
                        )
                        //invisible navigation link triggered programmatically
                        .background(
                            NavigationLink(destination: LazyClosureView(ContactDetails(delegate:SheetDismisserProtocol(), contact:contact)), tag:contact, selection:$navigationActive) { EmptyView() }
                                .opacity(0)
                         )
                    }
                }
                .onDelete(perform: { memberIdx in
                    let member = memberList[memberIdx.first!]
                    showActionSheet(title: Text("Remove user?"), description: self.group.mucType == "group" ? Text("Do you want to remove this user from this group? The user won't be able to enter it again until added back to the group.") : Text("Do you want to remove this user from this channel? The user will be able to enter it again.")) {
                        account.mucProcessor.setAffiliation("none", ofUser: member.contactJid, inMuc: self.group.contactJid)
                        self.showAlert(title: Text("User removed"), description: Text("\(memberList[memberIdx.first!].obj.contactJid)"))
                        memberList.remove(at: memberIdx.first!)
                    }
                })
            }
        }
        .onChange(of: memberList) { [previousMemberList = memberList] newMemberList in
            // only handle new members (added via the contact picker)
            for member in newMemberList {
                if !previousMemberList.contains(member) {
                    // add selected group member with affiliation member
                    affiliations[member] = "member"
                    account.mucProcessor.setAffiliation("member", ofUser:member.contactJid, inMuc:self.group.contactJid)
                    account.mucProcessor.inviteUser(member.contactJid, inMuc: self.group.contactJid)
                }
            }
        }
        .alert(isPresented: $showAlert, content: {
            Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton: .default(alertPrompt.dismissLabel))
        })
        .actionSheet(isPresented: $showActionSheet) {
            ActionSheet(
                title: actionSheetPrompt.title,
                message: actionSheetPrompt.message,
                buttons: [
                    .cancel(),
                    .destructive(
                        Text("Yes"),
                        action: actionSheetPrompt.closure
                    )
                ]
            )
        }
        .navigationBarTitle("Group Members", displayMode: .inline)
    }
}

struct MemberList_Previews: PreviewProvider {
    static var previews: some View {
        MemberList(mucContact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(2)));
    }
}
