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
    @StateObject var muc: ObservableKVOWrapper<MLContact>
    @State private var memberList: OrderedSet<ObservableKVOWrapper<MLContact>>
    @State private var affiliations: Dictionary<ObservableKVOWrapper<MLContact>, String>
    @State private var online: Dictionary<ObservableKVOWrapper<MLContact>, Bool>
    @State private var navigationActive: ObservableKVOWrapper<MLContact>?
    @State private var showAlert = false
    @State private var alertPrompt = AlertPrompt(dismissLabel: Text("Close"))
    @State private var showActionSheet = false
    @State private var actionSheetPrompt = ActionSheetPrompt()
    @StateObject private var overlay = LoadingOverlayState()

    init(mucContact: ObservableKVOWrapper<MLContact>) {
        account = MLXMPPManager.sharedInstance().getConnectedAccount(forID: mucContact.accountId)! as xmpp
        _muc = StateObject(wrappedValue:mucContact)
        _ownAffiliation = State(wrappedValue:"none")
        _memberList = State(wrappedValue:OrderedSet<ObservableKVOWrapper<MLContact>>())
        _affiliations = State(wrappedValue:[:])
        _online = State(wrappedValue:[:])
    }
    
    func updateMemberlist() {
        memberList = getContactList(viewContact:self.muc)
        ownAffiliation = DataLayer.sharedInstance().getOwnAffiliation(inGroupOrChannel:self.muc.obj) ?? "none"
        affiliations.removeAll(keepingCapacity:true)
        online.removeAll(keepingCapacity:true)
        for memberInfo in Array(DataLayer.sharedInstance().getMembersAndParticipants(ofMuc:self.muc.contactJid, forAccountId:account.accountNo)) {
            DDLogVerbose("Got member/participant entry: \(String(describing:memberInfo))")
            guard let jid = memberInfo["participant_jid"] as? String ?? memberInfo["member_jid"] as? String else {
                continue
            }
            let contact = ObservableKVOWrapper(MLContact.createContact(fromJid:jid, andAccountNo:account.accountNo))
            affiliations[contact] = memberInfo["affiliation"] as? String ?? "none"
            if let num = memberInfo["online"] as? NSNumber {
                online[contact] = num.boolValue
            } else {
                online[contact] = false
            }
        }
    }
    
    func performAction(_ title: Text, action: @escaping ()->Void) {
        self.account.mucProcessor.addUIHandler({_data in let data = _data as! NSDictionary
            DispatchQueue.main.async {
                hideLoadingOverlay(overlay)
                let success : Bool = data["success"] as! Bool;
                if !success {
                    showAlert(title: title, description: Text(data["errorMessage"] as? String ?? "Unknown error!"))
                }
            }
        }, forMuc:self.muc.contactJid)
        action()
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
        //we don't want to set affiliation=none in channels using deletion swipe (this does not delete the user)
        if self.muc.mucType == "channel" {
            return false
        }
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
        if let contactAffiliation = affiliations[contact], let contactOnline = online[contact] {
            var reinviteEntry: [String] = []
            if !contactOnline {
                reinviteEntry = ["reinvite"]
            }
            if self.muc.mucType == "group" {
                if ownAffiliation == "owner" {
                    return ["profile"] + reinviteEntry + ["owner", "admin", "member", "outcast"]
                } else {        //only admin left, because other affiliations don't call actionsAllowed at all
                    if ["member", "outcast"].contains(contactAffiliation) {
                        return ["profile"] + reinviteEntry + ["member", "outcast"]
                    } else {
                        //if this contact is a co-admin or owner, we aren't allowed to do much to their affiliation
                        //return contact affiliation because that should be displayed as selected in picker
                        return ["profile"] + reinviteEntry + [contactAffiliation]
                    }
                }
            } else {
                if ownAffiliation == "owner" {
                    return ["profile"] + reinviteEntry + ["owner", "admin", "member", "none", "outcast"]
                } else {        //only admin left, because other affiliations don't call actionsAllowed at all
                    if ["member", "none", "outcast"].contains(contactAffiliation) {
                        return ["profile"] + reinviteEntry + ["member", "none", "outcast"]
                    } else {
                        //if this contact is a co-admin or owner, we aren't allowed to do much to their affiliation
                        //return contact affiliation because that should be displayed as selected in picker
                        return ["profile"] + reinviteEntry + [contactAffiliation]
                    }
                }
            }
        }
        //fallback (should hopefully never be needed)
        DDLogWarn("Fallback for group/channel \(String(describing:self.muc.contactJid as String)): affiliation=\(String(describing:affiliations[contact])), online=\(String(describing:online[contact]))")
        if self.muc.mucType == "group" {
            return ["profile"]
        } else {
            return ["profile", "reinvite", "none"]
        }
    }

    var body: some View {
        List {
            Section(header: Text("\(self.muc.contactDisplayName as String) (affiliation: \(mucAffiliationToString(ownAffiliation)))")) {
                if ownAffiliation == "owner" || ownAffiliation == "admin" {
                    NavigationLink(destination: LazyClosureView(ContactPicker(account, initializeFrom: memberList, allowRemoval: false) { newMemberList in
                        for member in newMemberList {
                            if !memberList.contains(member) {
                                if self.muc.mucType == "group" {
                                    showLoadingOverlay(overlay, headlineView: Text("Adding new member"), descriptionView: Text("Adding \(member.contactJid as String)..."))
                                    performAction(Text("Error adding new member!")) {
                                        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0) {
                                            account.mucProcessor.setAffiliation("member", ofUser:member.contactJid, inMuc:self.muc.contactJid)
                                            account.mucProcessor.inviteUser(member.contactJid, inMuc: self.muc.contactJid)
                                        }
                                    }
                                } else {
                                    showLoadingOverlay(overlay, headlineView: Text("Inviting new participant"), descriptionView: Text("Adding \(member.contactJid as String)..."))
                                    performAction(Text("Error adding new participant!")) {
                                        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0) {
                                            account.mucProcessor.inviteUser(member.contactJid, inMuc: self.muc.contactJid)
                                        }
                                    }
                                }
                            }
                        }
                    })) {
                        if self.muc.mucType == "group" {
                            Text("Add members to group")
                        } else {
                            Text("Invite participants to channel")
                        }
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
                                        } else if newAffiliation == "reinvite" {
                                            showLoadingOverlay(overlay, headlineView: Text("Inviting user"), descriptionView: Text("Inviting user to this group/channel: \(contact.contactJid as String)"))
                                            performAction(Text("Error inviting user!")) {
                                                DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0) {
                                                    //first remove potential ban, then reinvite
                                                    if affiliations[contact] == "outcast" {
                                                        account.mucProcessor.setAffiliation(self.muc.mucType == "group" ? "member" : "none", ofUser:contact.contactJid, inMuc:self.muc.contactJid)
                                                    }
                                                    account.mucProcessor.inviteUser(contact.contactJid, inMuc: self.muc.contactJid)
                                                }
                                            }
                                        } else if newAffiliation == "outcast" {
                                            showActionSheet(title: Text("Block user?"), description: Text("Do you want to block this user from entering this group/channel?")) {
                                                DDLogVerbose("Changing affiliation of \(String(describing:contact)) to: \(String(describing:newAffiliation))...")
                                                showLoadingOverlay(overlay, headlineView: Text("Blocking member"), descriptionView: Text("Blocking \(contact.contactJid as String)"))
                                                performAction(Text("Error blocking user!")) {
                                                    DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0) {
                                                        account.mucProcessor.setAffiliation(newAffiliation, ofUser:contact.contactJid, inMuc:self.muc.contactJid)
                                                    }
                                                }
                                            }
                                        } else {
                                            DDLogVerbose("Changing affiliation of \(String(describing:contact)) to: \(String(describing:newAffiliation))...")
                                            showLoadingOverlay(overlay, headlineView: Text("Changing affiliation of member"), descriptionView: 
                                                Text("Changing \(contact.contactJid as String) to ") + Text(mucAffiliationToString(newAffiliation)))
                                            performAction(Text("Error changing affiliation!")) {
                                                DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0) {
                                                    account.mucProcessor.setAffiliation(newAffiliation, ofUser:contact.contactJid, inMuc:self.muc.contactJid)
                                                }
                                            }
                                        }
                                    }
                                ), label: EmptyView()) {
                                    ForEach(actionsAllowed(for:contact), id:\.self) { affiliation in
                                        Text(mucAffiliationToString(affiliation)).tag(affiliation)
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
                        showActionSheet(title: Text("Remove user?"), description: self.muc.mucType == "group" ? Text("Do you want to remove this user from this group? The user won't be able to enter it again until added back to the group.") : Text("Do you want to remove this user from this channel? The user will be able to enter it again.")) {
                            showLoadingOverlay(overlay, headlineView: Text("Removing member"), descriptionView: Text("Removing \(member.contactJid as String)..."))
                            performAction(Text("Error removing user!")) {
                                DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0) {
                                    account.mucProcessor.setAffiliation("none", ofUser: member.contactJid, inMuc: self.muc.contactJid)
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
                                    Text(mucAffiliationToString(affiliations[contact]))
                                }
                            }
                            .deleteDisabled(true)
                        }
                    }
                }
            }
        }
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
        .alert(isPresented: $showAlert, content: {
            Alert(title: alertPrompt.title, message: alertPrompt.message, dismissButton: .default(alertPrompt.dismissLabel))
        })
        .addLoadingOverlay(overlay)
        .navigationBarTitle(Text("Group Members"), displayMode: .inline)
        .onAppear {
            updateMemberlist()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalMucParticipantsAndMembersUpdated")).receive(on: RunLoop.main)) { notification in
            if let xmppAccount = notification.object as? xmpp, let contact = notification.userInfo?["contact"] as? MLContact {
                DDLogVerbose("Got muc participants/members update from account \(xmppAccount)...")
                if contact == self.muc {
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
