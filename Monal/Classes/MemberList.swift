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
    @State private var ownAffiliation: String;
    @StateObject var group: ObservableKVOWrapper<MLContact>
    @State private var memberList: OrderedSet<ObservableKVOWrapper<MLContact>>
    @State private var affiliations: Dictionary<ObservableKVOWrapper<MLContact>, String>
    @State private var navigationActive: ObservableKVOWrapper<MLContact>?
    @State private var showAlert = false
    @State private var alertPrompt = AlertPrompt(dismissLabel: Text("Close"))
    @State private var showActionSheet = false
    @State private var actionSheetPrompt = ActionSheetPrompt()
    @StateObject private var overlay = LoadingOverlayState()

    init(mucContact: ObservableKVOWrapper<MLContact>) {
        account = MLXMPPManager.sharedInstance().getConnectedAccount(forID: mucContact.accountId)! as xmpp
        _group = StateObject(wrappedValue:mucContact)
        _ownAffiliation = State(wrappedValue:"none")
        _memberList = State(wrappedValue:OrderedSet<ObservableKVOWrapper<MLContact>>())
        _affiliations = State(wrappedValue:[:])
    }
    
    func updateMemberlist() {
        memberList = getContactList(viewContact:group)
        ownAffiliation = DataLayer.sharedInstance().getOwnAffiliation(inGroupOrChannel:group.obj) ?? "none"
        var affiliationTmp = Dictionary<ObservableKVOWrapper<MLContact>, String>()
        for memberInfo in Array(DataLayer.sharedInstance().getMembersAndParticipants(ofMuc:group.contactJid, forAccountId:account.accountNo)) {
            guard let jid = memberInfo["participant_jid"] as? String ?? memberInfo["member_jid"] as? String else {
                continue
            }
            let contact = ObservableKVOWrapper(MLContact.createContact(fromJid:jid, andAccountNo:account.accountNo))
            affiliationTmp[contact] = memberInfo["affiliation"] as? String ?? "none"
        }
        affiliations = affiliationTmp
    }
    
    func performAction(_ title: Text, action: @escaping ()->Void) {
        action()
        self.account.mucProcessor.addUIHandler({_data in let data = _data as! NSDictionary
            DispatchQueue.main.async {
                hideLoadingOverlay(overlay)
                let success : Bool = data["success"] as! Bool;
                if !success {
                    showAlert(title: title, description: Text(data["errorMessage"] as! String))
                }
            }
        }, forMuc:group.contactJid)
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
    
    func actionsAllowed(for contact:ObservableKVOWrapper<MLContact>) -> [String] {
        if let contactAffiliation = affiliations[contact] {
            if ownAffiliation == "owner" {
                return ["profile", "owner", "admin", "member", "outcast"]
            } else {        //only admin left, because other affiliations don't call actionsAllowed at all
                if ["member", "outcast"].contains(contactAffiliation) {
                    return ["profile", "member", "outcast"]
                } else {
                    //return contact affiliation because that should be displayed as selected in picker
                    return ["profile", contactAffiliation]
                }
            }
        }
        return ["profile"]
    }
    
    func affiliationToString(_ affiliation: String?) -> String {
        if let affiliation = affiliation {
            if affiliation == "owner" {
                return NSLocalizedString("Owner", comment:"muc affiliation")
            } else if affiliation == "admin" {
                return NSLocalizedString("Admin", comment:"muc affiliation")
            } else if affiliation == "member" {
                return NSLocalizedString("Member", comment:"muc affiliation")
            } else if affiliation == "outcast" {
                return NSLocalizedString("Blocked", comment:"muc affiliation")
            } else if affiliation == "profile" {
                return NSLocalizedString("Open contact details", comment:"")
            }
        }
        return NSLocalizedString("<unknown>", comment:"muc affiliation")
    }

    var body: some View {
        List {
            Section(header: Text("\(self.group.contactDisplayName as String) (affiliation: \(affiliationToString(ownAffiliation)))")) {
                if ownAffiliation == "owner" || ownAffiliation == "admin" {
                    NavigationLink(destination: LazyClosureView(ContactPicker(account, initializeFrom: memberList, allowRemoval: false) { newMemberList in
                        for member in newMemberList {
                            if !memberList.contains(member) {
                                showLoadingOverlay(overlay, headlineView: Text("Adding new member"), descriptionView: Text("Adding \(member.contactJid as String)..."))
                                performAction(Text("Error adding new member!")) {
                                    DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0) {
                                        account.mucProcessor.setAffiliation("member", ofUser:member.contactJid, inMuc:self.group.contactJid)
                                        account.mucProcessor.inviteUser(member.contactJid, inMuc: self.group.contactJid)
                                    }
                                }
                            }
                        }
                    })) {
                        Text("Add Group Members")
                    }
                    
                    ForEach(memberList, id:\.self) { contact in
                        if !contact.isSelfChat {
                            HStack(alignment: .center) {
                                ContactEntry(contact:contact)
                                Spacer()
                                Picker(selection: Binding<String>(
                                    get: { affiliations[contact] ?? "none" },
                                    set: { newAffiliation in
                                        if newAffiliation == affiliations[contact] {
                                            return
                                        }
                                        if newAffiliation == "profile" {
                                            DDLogVerbose("Activating navigation to \(String(describing:contact))")
                                            navigationActive = contact
                                        } else if newAffiliation == "outcast" {
                                            showActionSheet(title: Text("Block user?"), description: Text("Do you want to block this user from entering this group/channel?")) {
                                                DDLogVerbose("Changing affiliation of \(String(describing:contact)) to: \(String(describing:newAffiliation))...")
                                                showLoadingOverlay(overlay, headlineView: Text("Blocking member"), descriptionView: Text("Blocking \(contact.contactJid as String)..."))
                                                performAction(Text("Error blocking user!")) {
                                                    DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0) {
                                                        account.mucProcessor.setAffiliation(newAffiliation, ofUser:contact.contactJid, inMuc:self.group.contactJid)
                                                    }
                                                }
                                            }
                                        } else {
                                            DDLogVerbose("Changing affiliation of \(String(describing:contact)) to: \(String(describing:newAffiliation))...")
                                            showLoadingOverlay(overlay, headlineView: Text("Changing affiliation of member"), descriptionView: 
                                                Text("Changing \(contact.contactJid as String) to ") + Text(affiliationToString(newAffiliation)) + Text("..."))
                                            performAction(Text("Error changing affiliation!")) {
                                                DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0) {
                                                    account.mucProcessor.setAffiliation(newAffiliation, ofUser:contact.contactJid, inMuc:self.group.contactJid)
                                                }
                                            }
                                        }
                                    }
                                ), label: EmptyView()) {
                                    ForEach(actionsAllowed(for:contact), id:\.self) { affiliation in
                                        Text(affiliationToString(affiliation)).tag(affiliation)
                                    }
                                }
                                .pickerStyle(.menu)
                                //invisible navigation link triggered programmatically
                                .background(
                                    NavigationLink(destination: LazyClosureView(ContactDetails(delegate:SheetDismisserProtocol(), contact:contact)), tag:contact, selection:$navigationActive) { EmptyView() }
                                        .opacity(0)
                                )
                            }
                            .deleteDisabled(
                                !ownUserHasAffiliationToRemove(contact: contact)
                            )
                        }
                    }
                    .onDelete(perform: { memberIdx in
                        let member = memberList[memberIdx.first!]
                        showActionSheet(title: Text("Remove user?"), description: self.group.mucType == "group" ? Text("Do you want to remove this user from this group? The user won't be able to enter it again until added back to the group.") : Text("Do you want to remove this user from this channel? The user will be able to enter it again.")) {
                            showLoadingOverlay(overlay, headlineView: Text("Removing member"), descriptionView: Text("Removing \(member.contactJid as String)..."))
                            performAction(Text("Error removing user!")) {
                                DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0) {
                                    account.mucProcessor.setAffiliation("none", ofUser: member.contactJid, inMuc: self.group.contactJid)
                                }
                            }
                        }
                    })
                } else {
                    ForEach(memberList, id:\.self) { contact in
                        if !contact.isSelfChat {
                            NavigationLink(destination: LazyClosureView(ContactDetails(delegate:SheetDismisserProtocol(), contact:contact))) {
                                HStack(alignment: .center) {
                                    ContactEntry(contact:contact)
                                    Spacer()
                                    Text(affiliationToString(affiliations[contact]))
                                }
                            }
                            .deleteDisabled(true)
                        }
                    }
                }
            }
        }
        .addLoadingOverlay(overlay)
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
        .onAppear {
            updateMemberlist()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalMucParticipantsAndMembersUpdated")).receive(on: RunLoop.main)) { notification in
            if let xmppAccount = notification.object as? xmpp, let contact = notification.userInfo?["contact"] as? MLContact {
                DDLogVerbose("Got muc participants/members update from account \(xmppAccount)...")
                if contact == group {
                    updateMemberlist()
                    hideLoadingOverlay(overlay)
                }
            }
        }
    }
}

struct MemberList_Previews: PreviewProvider {
    static var previews: some View {
        MemberList(mucContact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(2)));
    }
}
