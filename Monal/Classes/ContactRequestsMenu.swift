//
//  ContactRequestsMenu.swift
//  Monal
//
//  Created by Jan on 27.10.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

struct ContactRequestsMenuEntry: View {
    let contact : MLContact
    @State private var isDeleted = false
    
    var body: some View {
        HStack {
            Text(contact.contactJid)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Group {
                Button {
                    let appDelegate = UIApplication.shared.delegate as! MonalAppDelegate
                    appDelegate.openChat(of:contact)
                } label: {
                    Image(systemName: "text.bubble")
                        .foregroundStyle(Color.primary)
                }
                //see https://www.hackingwithswift.com/forums/swiftui/tap-button-in-hstack-activates-all-button-actions-ios-14-swiftui-2/2952
                .buttonStyle(BorderlessButtonStyle())
                
                Button {
                    // deny request
                    MLXMPPManager.sharedInstance().remove(contact)
                } label: {
                    Image(systemName: "trash.circle")
                        .foregroundStyle(Color.red)
                }
                //see https://www.hackingwithswift.com/forums/swiftui/tap-button-in-hstack-activates-all-button-actions-ios-14-swiftui-2/2952
                .buttonStyle(BorderlessButtonStyle())
                
                Button {
                    // accept request
                    MLXMPPManager.sharedInstance().add(contact)
                    let appDelegate = UIApplication.shared.delegate as! MonalAppDelegate
                    appDelegate.openChat(of:contact)
                } label: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Color.green)
                }
                //see https://www.hackingwithswift.com/forums/swiftui/tap-button-in-hstack-activates-all-button-actions-ios-14-swiftui-2/2952
                .buttonStyle(BorderlessButtonStyle())
            }
            .font(.largeTitle)
        }
    }
}

struct ContactRequestsMenu: View {
    @State var pendingRequests: [xmpp:[MLContact]] = [:]
    @State var connectedAccounts: [Int:xmpp] = [:]
    
    func updateRequests() {
        let requests = DataLayer.sharedInstance().allContactRequests() as! [MLContact]
        connectedAccounts.removeAll()
        for account in MLXMPPManager.sharedInstance().connectedXMPP as! [xmpp] {
            connectedAccounts[account.accountNo.intValue] = account
        }
        pendingRequests.removeAll()
        for contact in requests {
            //add only requests having an enabled (dubbed connected) account
            //(should be a noop because allContactRequests() returns only enabled accounts)
            if let account = connectedAccounts[contact.accountId.intValue] {
                if pendingRequests[account] == nil {
                    pendingRequests[account] = []
                }
                pendingRequests[account]!.append(contact)
            }
        }
    }
    
    var body: some View {
        Section(header: Text("Allowing someone to add you as a contact lets them see your profile picture and when you are online.")) {
            if(pendingRequests.isEmpty) {
                Text("No pending constact requests")
                    .foregroundColor(.secondary)
            } else {
                List {
                    ForEach(pendingRequests.sorted(by:{ $0.0.connectionProperties.identity.jid < $1.0.connectionProperties.identity.jid }), id: \.key) { account, requests in
                        if connectedAccounts.count == 1 {
                            ForEach(requests.indices, id: \.self) { idx in
                                ContactRequestsMenuEntry(contact: requests[idx])
                            }
                        } else {
                            Section(header: Text("Account: \(account.connectionProperties.identity.jid)")) {
                                ForEach(requests.indices, id: \.self) { idx in
                                    ContactRequestsMenuEntry(contact: requests[idx])
                                }
                            }
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalContactRefresh")).receive(on: RunLoop.main)) { notification in
            updateRequests()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalContactRemoved")).receive(on: RunLoop.main)) { notification in
            updateRequests()
        }
        .onAppear {
            updateRequests()
        }
    }
}

struct ContactRequestsMenu_Previews: PreviewProvider {
    static var previews: some View {
        ContactRequestsMenu()
    }
}
