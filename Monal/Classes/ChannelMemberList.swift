//
//  ChannelMemberList.swift
//  Monal
//
//  Created by Friedrich Altheide on 17.02.24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import OrderedCollections

struct ChannelMemberList: View {
    @State private var channelParticipants: OrderedDictionary<String, String>
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
        _channelParticipants = State(wrappedValue: nickSet)
    }

    var body: some View {
        List {
            Section(header: Text(self.channel.obj.contactDisplayName)) {
                ForEach(self.channelParticipants.sorted(by: <), id: \.self.key) { participant in
                    ZStack(alignment: .topLeading) {
                        HStack(alignment: .center) {
                            Text(participant.key)
                            Spacer()
                            if participant.value == "owner" {
                                Text(NSLocalizedString("Owner", comment: ""))
                            } else if participant.value == "admin" {
                                Text(NSLocalizedString("Admin", comment: ""))
                            } else {
                                Text(NSLocalizedString("Participant", comment: ""))
                            }
                        }
                    }
                }
            }
        }
        .navigationBarTitle(NSLocalizedString("Channel Participants", comment: ""), displayMode: .inline)
    }
}

struct ChannelMemberList_Previews: PreviewProvider {
    static var previews: some View {
        ChannelMemberList(mucContact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(3)));
    }
}
