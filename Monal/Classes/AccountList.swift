//
//  AccountList.swift
//  Monal
//
//  Created by lissine on 30/11/2024.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

private class Account: Identifiable {
    let accountID: NSNumber
    let username: String
    let domain: String
    var enabled: Bool
    var jid: String {
        return username+"@"+domain
    }
    var connected: Bool {
        return MLXMPPManager.sharedInstance().isAccount(forIdConnected: self.accountID)
    }
    var connectedTime: Date {
        return MLXMPPManager.sharedInstance().connectedTime(for: self.accountID)
    }
    var avatar: UIImage {
        return MLImageManager.sharedInstance().getIconFor(MLContact.createContact(fromJid: self.jid, andAccountID: self.accountID)) ?? UIImage(named: "noicon")!
    }
    // Conformance to the Identifiable protocol
    var id: NSNumber {
        return accountID
    }

    init(account: [String: Any]) {
        self.accountID = account["account_id"] as! NSNumber
        self.username = account["username"] as! String
        self.domain = account["domain"] as! String
        self.enabled = account["enabled"] as! Bool
    }
}

private struct AccountEntry: View {
    let account: Account
    let uptimeFormatter: DateFormatter

    init(account: Account) {
        self.account = account
        self.uptimeFormatter = DateFormatter()
        uptimeFormatter.dateStyle = .short
        uptimeFormatter.timeStyle = .short
        uptimeFormatter.doesRelativeDateFormatting = true
    }

    var connectionStatusString: String {
        if account.enabled && account.connected {
            return String(format: NSLocalizedString("Connected since: %@", comment: ""), uptimeFormatter.string(from: account.connectedTime))
        } else if account.enabled && !account.connected {
            return NSLocalizedString("Connecting...", comment: "")
        } else {
            return NSLocalizedString("Account disabled", comment: "")
        }
    }

    var body: some View {
        HStack {
            Image(uiImage: account.avatar)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .padding(.leading, -3)
                .padding(.trailing, 4)
            VStack {
                Text(account.jid)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(self.connectionStatusString)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
            Image(systemName: account.enabled ? (account.connected ? "checkmark.circle.fill" : "checkmark.circle") : "circle")
                .foregroundStyle(Color.accentColor)
        }
    }
}

struct AccountList: View {
    @State private var accounts: [Account] = getAccountList()

    private static func getAccountList() -> [Account] {
        return (DataLayer.sharedInstance().accountList() as! [[String: Any]]).map { Account(account: $0) }
    }
    private func refreshAccountList() {
        self.accounts = AccountList.getAccountList()
    }

    var body: some View {
        List {
            ForEach(accounts) { account in
                NavigationLink {
                    LazyClosureView(EmptyView())
                } label: {
                    AccountEntry(account: account)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalAccountStatusChanged)).receive(on: RunLoop.main)) { notification in
            DispatchQueue.main.async {
                DDLogVerbose("Refreshing the account list in the Settings view")
                refreshAccountList()
            }
        }
    }
}
