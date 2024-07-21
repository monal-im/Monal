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
                        .accentColor(.primary)
                }
                //see https://www.hackingwithswift.com/forums/swiftui/tap-button-in-hstack-activates-all-button-actions-ios-14-swiftui-2/2952
                .buttonStyle(BorderlessButtonStyle())
                
                Button {
                    // deny request
                    MLXMPPManager.sharedInstance().remove(contact)
                } label: {
                    Image(systemName: "trash.circle")
                        .accentColor(.red)
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
                        .accentColor(.green)
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
    
    func updateRequests() {
        let requests = DataLayer.sharedInstance().allContactRequests() as! [MLContact]
        var connectedAccounts: [Int:xmpp] = [:]
        for account in MLXMPPManager.sharedInstance().connectedXMPP as! [xmpp] {
            connectedAccounts[account.accountNo.intValue] = account
        }
        self.pendingRequests.removeAll()
        for contact in requests {
            //add only requests having an enabled (dubbed connected) account
            //(should be a noop because allContactRequests() returns only enabled accounts)
            if let account = connectedAccounts[contact.accountId.intValue] {
                if self.pendingRequests[account] == nil {
                    self.pendingRequests[account] = []
                }
                self.pendingRequests[account]!.append(contact)
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
                    ForEach(self.pendingRequests.sorted(by:{ $0.0.connectionProperties.identity.jid < $1.0.connectionProperties.identity.jid }), id: \.key) { account, requests in
                        Section(header: Text("Account: \(account.connectionProperties.identity.jid)")) {
                            ForEach(requests.indices, id: \.self) { idx in
                                ContactRequestsMenuEntry(contact: requests[idx])
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
