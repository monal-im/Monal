//
//  AccountPicker.swift
//  Monal
//
//  Created by Thilo Molitor on 20.01.23.
//  Copyright © 2023 monal-im.org. All rights reserved.
//

struct AccountPicker: View {
    let delegate: SheetDismisserProtocol
    let contacts: [MLContact]
    let callType: MLCallType
#if IS_ALPHA
    let appLogoId = "AlphaAppLogo"
#elseif IS_QUICKSY
    let appLogoId = "QuicksyAppLogo"
#else
    let appLogoId = "AppLogo"
#endif
    
    init(delegate:SheetDismisserProtocol, contacts:[MLContact], callType: MLCallType) {
        self.delegate = delegate
        self.contacts = contacts
        self.callType = callType
    }
    
    var body: some View {
        //ScrollView {
            VStack {
                HStack () {
                    Image(decorative: appLogoId)
                        .resizable()
                        .frame(width: CGFloat(120), height: CGFloat(120), alignment: .center)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding()                    
                    Text("You are trying to call '\(contacts.first!.contactDisplayName)' (\(contacts.first!.contactJid)), but this contact can be reached using different accounts. Please select the account you want to place the outgoing call with.")
                        .padding()
                        .padding(.leading, -16.0)
                }
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.systemBackground))
                
                List {
                    ForEach(contacts) { contact in
                        if let accountEntry = DataLayer.sharedInstance().details(forAccount:contact.accountId) {
                            let accountJid = "\(accountEntry["username"] ?? "<unknown>" as NSString)@\(accountEntry["domain"] ?? "<unknown>" as NSString)"
                            let accountContact = MLContact.createContact(fromJid:accountJid, andAccountNo:accountEntry["account_id"] as! NSNumber)
                            Button {
                                (UIApplication.shared.delegate as! MonalAppDelegate).activeChats!.call(contact, with:callType)
                            } label: {
                                ContactEntry(contact:ObservableKVOWrapper(accountContact), selfnotesPrefix:false)
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
        AccountPicker(delegate:delegate, contacts:[MLContact.makeDummyContact(0)], callType:.audio)
    }
}
