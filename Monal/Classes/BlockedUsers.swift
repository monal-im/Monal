//
//  BlockedUsers.swift
//  Monal
//
//  Created by lissine on 10/9/2024.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

struct BlockedUsers: View {
    let xmppAccount: xmpp
    static private let jidPattern = "^([^@]+@)?[^/\\n]+(\\..{2,})?(/.+)?$"

    @State private var blockedJids: [String] = []
    @State private var jidToBlock = ""
    @State private var showAddingToBlocklistForm = false
    @State private var showBlockingUnsupportedPlaceholder = false
    @State private var showInvalidJidAlert = false
    @StateObject private var overlay = LoadingOverlayState()

    private var blockingUnsupported: Bool {
        return !xmppAccount.connectionProperties.serverDiscoFeatures.contains("urn:xmpp:blocking")
    }

    private func reloadBlocksFromDB() {
        self.blockedJids = DataLayer.sharedInstance().blockedJids(forAccount: xmppAccount.accountID)
    }

    var body: some View {
        if showBlockingUnsupportedPlaceholder {
            ContentUnavailableShimView(NSLocalizedString("Blocking unsupported", comment: ""), systemImage: "iphone.homebutton.slash", description: Text("Your server does not support blocking (XEP-0191)."))
        } else {
            List {
                ForEach(blockedJids, id: \.self) { blockedJid in
                    Text(blockedJid)
                }
                .onDelete { indexSet in
                    for row in indexSet {
                        showLoadingOverlay(overlay, headlineView: Text("Saving changes to server"), descriptionView: Text(""))
                        // unblock the jid
                        MLXMPPManager.sharedInstance().block(false, fullJid: self.blockedJids[row], onAccount: self.xmppAccount.accountID)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(Text("Blocked Users"))
            .animation(.default, value: blockedJids)
            .onAppear {
                if !(xmppAccount.accountState.rawValue >= xmppState.stateBound.rawValue && xmppAccount.connectionProperties.accountDiscoDone) {
                    showLoadingOverlay(overlay, headlineView: Text("Account is connecting..."), descriptionView: Text(""))
                }
                showBlockingUnsupportedPlaceholder = blockingUnsupported
                reloadBlocksFromDB()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalAccountDiscoDone")).receive(on: RunLoop.main)) { notification in
                guard let notificationAccountID = notification.userInfo?["accountID"] as? NSNumber,
                      notificationAccountID.intValue == xmppAccount.accountID.intValue else {
                    return
                }

                // recompute this state variable, so the view is re-rendered if it changed.
                showBlockingUnsupportedPlaceholder = blockingUnsupported
                reloadBlocksFromDB()
                hideLoadingOverlay(overlay)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalBlockListRefresh")).receive(on: RunLoop.main)) { notification in
                guard let notificationAccountID = notification.userInfo?["accountID"] as? NSNumber,
                      notificationAccountID.intValue == xmppAccount.accountID.intValue else {
                    return
                }

                DispatchQueue.main.async {
                    reloadBlocksFromDB()
                    DDLogVerbose("Got block list update from account \(xmppAccount)...")
                    hideLoadingOverlay(overlay)
                }

            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showAddingToBlocklistForm = true
                    }, label: {
                        Image(systemName: "plus")
                    })
                }
            }
            .alert(NSLocalizedString("Enter the jid that you want to block", comment: ""), isPresented: $showAddingToBlocklistForm, actions: {
                TextField("user@example.org/resource", text: $jidToBlock)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()

                Button(NSLocalizedString("Block", comment: ""), role: .destructive) {
                    guard (jidToBlock.range(of: BlockedUsers.jidPattern, options: .regularExpression) != nil) else {
                        showInvalidJidAlert = true
                        return
                    }

                    showLoadingOverlay(overlay, headlineView: Text("Saving changes to server"), descriptionView: Text(""))
                    // block the jid
                    MLXMPPManager.sharedInstance().block(true, fullJid: jidToBlock, onAccount: self.xmppAccount.accountID)
                }

                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel, action: {})
            }
            )
            // If .onDisappear is applied to the alert or any of its subviews, its perform action won't
            // get executed until the whole Blocked Users view is dismissed. Therefore .onChange is used instead
            .onChange(of: showAddingToBlocklistForm) { _ in
                if !showAddingToBlocklistForm {
                    // The alert has been dismissed
                    jidToBlock = ""
                }
            }
            .alert(NSLocalizedString("Input is not a valid jid", comment: ""), isPresented: $showInvalidJidAlert, actions: {})
            .addLoadingOverlay(overlay)
        }
    }
}
