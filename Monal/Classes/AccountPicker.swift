//
//  AccountPicker.swift
//  Monal
//
//  Created by Thilo Molitor on 20.01.23.
//  Copyright © 2023 monal-im.org. All rights reserved.
//

import SwiftUI
import monalxmpp

struct AccountPicker: View {
    let delegate: SheetDismisserProtocol
    let contacts: [MLContact]
#if IS_ALPHA
    let appLogoId = "AlphaAppLogo"
#else
    let appLogoId = "AppLogo"
#endif
    
    init(delegate:SheetDismisserProtocol, contacts:[MLContact]) {
        self.delegate = delegate
        self.contacts = contacts
    }
    
    var body: some View {
        //ScrollView {
            VStack {
                HStack () {
                    Image(decorative: appLogoId)
                        .resizable()
                        .frame(width: CGFloat(120), height: CGFloat(120), alignment: .center)
                        .padding()                    
                    Text("You are trying to call jid '\(contacts.first!.contactJid)', but this contact can be reached using different accounts. Please select the account you want to place the outgoing call with.")
                        .padding()
                        .padding(.leading, -16.0)
                }
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.systemBackground))
                
                let appDelegate = UIApplication.shared.delegate as! MonalAppDelegate
                List {
                    ForEach(contacts) { contact in
                        if let account_entry = DataLayer.sharedInstance().details(forAccount:contact.accountId) {
                            let account_jid = "\(account_entry["username"] ?? "<unknown>" as NSString)@\(account_entry["domain"] ?? "<unknown>" as NSString)"
                            let account_contact = MLContact.createContact(fromJid:account_jid, andAccountNo:account_entry["id"] as! NSNumber)
                            let account_avatar = MLImageManager.sharedInstance().getIconFor(account_contact)!
                            Button {
                                appDelegate.activeChats?.call(contact)
                            } label: {
                                HStack(alignment: .center) {
                                    Image(uiImage: account_avatar)
                                        .resizable()
                                        .frame(width: 40, height: 40, alignment: .center)
                                    VStack(alignment: .leading) {
                                        Text(account_contact.contactDisplayName as String)
                                        Text(account_contact.contactJid as String).font(.footnote).opacity(0.6)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        //}
        .textFieldStyle(.roundedBorder)
        .navigationBarTitle(Text("Account Picker"))
        .accentColor(monalGreen)
    }
}

struct AccountPicker_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        AccountPicker(delegate:delegate, contacts:[MLContact.makeDummyContact(0)])
    }
}
