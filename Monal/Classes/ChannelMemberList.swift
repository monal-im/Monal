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
    @ObservedObject var channel: ObservableKVOWrapper<MLContact>
    private let account: xmpp?

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

    init(channelContact: ObservableKVOWrapper<MLContact>) {
        self.account = MLXMPPManager.sharedInstance().getConnectedAccount(forID: channelContact.obj.accountId)! as xmpp
        self.channel = channelContact;

        let jidList = Array(DataLayer.sharedInstance().getMembersAndParticipants(ofMuc: channelContact.obj.contactJid, forAccountId: channelContact.obj.accountId))
        var nickSet : OrderedDictionary<String, String> = OrderedDictionary()
        for jidDict in jidList {
            if let nick = jidDict["room_nick"] as? String {
                nickSet.updateValue(jidDict["affiliation"]! as! String, forKey: nick)
            }
        }
        _channelMembers = State(wrappedValue: nickSet)
    }
}

/*struct ChannelMemberList_Previews: PreviewProvider {
    static var previews: some View {
        // TODO some dummy views, requires a dummy xmpp obj
        // ChannelMemberList(channelContact: nil);
    }
}*/
