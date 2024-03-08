//
//  ChannelMemberList.swift
//  Monal
//
//  Created by Friedrich Altheide on 17.02.24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import SwiftUI
import monalxmpp
import OrderedCollections

struct ChannelMemberList: View {
    @State private var channelMembers: OrderedDictionary<String, String>
    @StateObject var channel: ObservableKVOWrapper<MLContact>
    private let account: xmpp

    init(mucContact: ObservableKVOWrapper<MLContact>) {
        self.account = MLXMPPManager.sharedInstance().getConnectedAccount(forID: mucContact.accountId)! as xmpp
        _channel = StateObject(wrappedValue: mucContact)
        
        let jidList = Array(DataLayer.sharedInstance().getMembersAndParticipants(ofMuc: mucContact.contactJid, forAccountId: mucContact.accountId))
        var nickSet : OrderedDictionary<String, String> = OrderedDictionary()
        for jidDict in jidList {
            if let nick = jidDict["room_nick"] as? String {
                nickSet.updateValue((jidDict["affiliation"] as? String) ?? "none", forKey:nick)
            }
        }
        _channelMembers = State(wrappedValue: nickSet)
    }

    var body: some View {
        List {
            Section(header: Text(self.channel.obj.contactDisplayName)) {
                ForEach(self.channelMembers.sorted(by: <), id: \.self.key) {
                    member in
                    ZStack(alignment: .topLeading) {
                        HStack(alignment: .center) {
                            Text(member.key)
                            Spacer()
                            if member.value == "owner" {
                                Text(NSLocalizedString("Owner", comment: ""))
                            } else if member.value == "admin" {
                                Text(NSLocalizedString("Admin", comment: ""))
                            } else {
                                Text(NSLocalizedString("Member", comment: ""))
                            }
                        }
                    }
                }
            }
        }
        .navigationBarTitle("Channel Members", displayMode: .inline)
    }
}

struct ChannelMemberList_Previews: PreviewProvider {
    static var previews: some View {
        ChannelMemberList(mucContact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(3)));
    }
}
