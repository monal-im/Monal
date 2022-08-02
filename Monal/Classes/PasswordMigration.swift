//
//  PasswordMigration.swift
//  Monal
//
//  Created by Thilo Molitor on 01.08.22.
//  Copyright © 2022 monal-im.org. All rights reserved.
//

import SwiftUI
import monalxmpp

struct PasswordMigration: View {
    let delegate: SheetDismisserProtocol
    @State var needingMigration: [Int:[String:NSObject]]
#if IS_ALPHA
    let appLogoId = "AlphaAppLogo"
#else
    let appLogoId = "AppLogo"
#endif
    
    init(delegate:SheetDismisserProtocol, needingMigration:[[String:NSObject]]) {
        self.delegate = delegate
        var tmpState = [Int:[String:NSObject]]()
        for entry in needingMigration {
            let id = (entry["account_id"] as! NSNumber).intValue
            tmpState[id] = entry
        }
        self.needingMigration = tmpState
        DDLogInfo("Migration needed: \(String(describing:self.needingMigration))")
    }
    
    var body: some View {
        //ScrollView {
            VStack {
                HStack () {
                    Image(decorative: appLogoId)
                        .resizable()
                        .frame(width: CGFloat(120), height: CGFloat(120), alignment: .center)
                        .padding()                    
                    Text("Your accounts got deactivated, because you restored an iCloud backup of this App. Please reenter your passwords to activate them again.")
                        .padding()
                        .padding(.leading, -16.0)
                }
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.systemBackground))
                
                List {
                    ForEach(Array(self.needingMigration.keys.enumerated()), id:\.element) { _, id in
                        let jid = "\(self.needingMigration[id]?["username"] ?? "<unknown>" as NSString)@\(self.needingMigration[id]?["domain"] ?? "<unknown>" as NSString)"
                        VStack {
                            Toggle(jid, isOn:Binding(
                                //our toggle is on, if we have a password AND the account is in enabled state
                                //(e.g. the user can enter a password, but keep the account disabled, if he wants)
                                get: { (self.needingMigration[id]?["password"] as? String ?? "") != "" && (self.needingMigration[id]?["enabled"] as! NSNumber).boolValue },
                                set: {
                                    if((self.needingMigration[id]?["password"] as? String ?? "") != "") {
                                        self.needingMigration[id]?["enabled"] = NSNumber(value:$0)
                                    }
                                }
                            ))
                            
                            SecureField("Password", text:Binding(
                                get: { self.needingMigration[id]?["password"] as? String ?? "" },
                                set: {
                                    self.needingMigration[id]?["password"] = $0 as NSString
                                    if($0.count > 0) {
                                        //first change? --> activate account and use "needs_password_migration" to record
                                        //the fact that we just activated this account automatically
                                        //(making the password field empty will reset this)
                                        if((self.needingMigration[id]?["needs_password_migration"] as! NSNumber).boolValue) {
                                            self.needingMigration[id]?["enabled"] = NSNumber(value:true)
                                            self.needingMigration[id]?["needs_password_migration"] = NSNumber(value:false)
                                        }
                                    //reset our "account automatically activated" flag and deactivate our account
                                    } else {
                                        self.needingMigration[id]?["enabled"] = NSNumber(value:false)
                                        self.needingMigration[id]?["needs_password_migration"] = NSNumber(value:true)
                                    }
                                }
                            ))
                            .addClearButton(text:Binding(
                                get: { self.needingMigration[id]?["password"] as? String ?? "" },
                                set: { self.needingMigration[id]?["password"] = $0 as NSString }
                            ))
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        //}
        .textFieldStyle(.roundedBorder)
        .navigationBarTitle(Text("Migration Assistant"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack{
                    Button(action: {
                        DDLogInfo("Saving migrated accounts: \(String(describing:self.needingMigration))")
                        for id in self.needingMigration.keys {
                            var dic = self.needingMigration[id]!
                            //don't show this migration dialog again, even if the user did not activate this account
                            dic["needs_password_migration"] = NSNumber(value:false)
                            if let password = dic["password"] as? String, password.count > 0 {
                                DDLogDebug("Updating account in DB: enabled=\(String(describing:dic["enabled"])), needs_password_migration=\(String(describing:dic["needs_password_migration"])), password.count=\(password.count)")
                                DataLayer.sharedInstance().updateAccoun(with:dic)
                                MLXMPPManager.sharedInstance().updatePassword(password, forAccount:dic["account_id"] as! NSNumber)
                                if((self.needingMigration[id]?["enabled"] as! NSNumber).boolValue) {
                                    DDLogDebug("Connecting now enabled account...")
                                    MLXMPPManager.sharedInstance().connectAccount(dic["account_id"] as! NSNumber)
                                }
                            } else {
                                DDLogDebug("Updating account in DB: enabled=\(String(describing:dic["enabled"])), needs_password_migration=\(String(describing:dic["needs_password_migration"])), password.count=0")
                                DataLayer.sharedInstance().updateAccoun(with:dic)
                            }
                        }
                        NotificationCenter.default.post(name:Notification.Name("kMonalRefresh"), object:nil);
                        self.delegate.dismiss()
                    }, label: {
                        Text("Done")
                    })
                }
            }
        }
        .accentColor(monalGreen)
    }
}

func previewMock() -> [[String:NSObject]] {
    return [
        [
            "account_id": NSNumber(value:1),
            "enabled": NSNumber(value:false),
            "needs_password_migration": NSNumber(value:true),
            "username": "user1" as NSString,
            "domain": "example.org" as NSString
        ],
        [
            "account_id": NSNumber(value:2),
            "enabled": NSNumber(value:false),
            "needs_password_migration": NSNumber(value:true),
            "username": "user2" as NSString,
            "domain": "example.com" as NSString
        ]
    ]
}

struct PasswordMigration_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        PasswordMigration(delegate:delegate, needingMigration:previewMock())
    }
}
