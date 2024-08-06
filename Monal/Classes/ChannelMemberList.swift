//
//  ChannelMemberList.swift
//  Monal
//
//  Created by Friedrich Altheide on 17.02.24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

import OrderedCollections

struct ChannelMemberList: View {
    private let account: xmpp
    @State private var ownAffiliation: String;
    @StateObject var channel: ObservableKVOWrapper<MLContact>
    @State private var participants: OrderedDictionary<String, String>

    init(mucContact: ObservableKVOWrapper<MLContact>) {
        account = (mucContact.account as xmpp?)!
        _channel = StateObject(wrappedValue:mucContact)
        _ownAffiliation = State(wrappedValue:"none")
        _participants = State(wrappedValue:OrderedDictionary<String, String>())
    }
    
    func updateParticipantList() {
        ownAffiliation = DataLayer.sharedInstance().getOwnAffiliation(inGroupOrChannel:channel.obj) ?? "none"
        participants.removeAll(keepingCapacity:true)
        for memberInfo in Array(DataLayer.sharedInstance().getMembersAndParticipants(ofMuc:channel.contactJid, forAccountId:account.accountNo)) {
            //ignore ourselves
            if let jid = memberInfo["participant_jid"] as? String ?? memberInfo["member_jid"] as? String {
                if jid == account.connectionProperties.identity.jid {
                    continue
                }
            }
            if let nick = memberInfo["room_nick"] as? String {
                participants[nick] = memberInfo["affiliation"] as? String ?? "none"
            }
        }
        participants.sort {
            (mucAffiliationToInt($0.value), $0.key) < (mucAffiliationToInt($1.value), $1.key)
        }
    }
    

    var body: some View {
        List {
            Section(header: Text("\(self.channel.contactDisplayName as String) (affiliation: \(mucAffiliationToString(ownAffiliation)))")) {
                ForEach(participants.keys, id: \.self) { participant_key in
                    ZStack(alignment: .topLeading) {
                        HStack(alignment: .center) {
                            Text(participant_key)
                            Spacer()
                            Text(mucAffiliationToString(participants[participant_key]))
                        }
                    }
                }
            }
        }
        .navigationBarTitle(Text("Channel Participants"), displayMode: .inline)
        .onAppear {
            updateParticipantList()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalMucParticipantsAndMembersUpdated")).receive(on: RunLoop.main)) { notification in
            if let xmppAccount = notification.object as? xmpp, let contact = notification.userInfo?["contact"] as? MLContact {
                DDLogVerbose("Got muc participants/members update from account \(xmppAccount)...")
                if contact == channel {
                    updateParticipantList()
                }
            }
        }
    }
}

struct ChannelMemberList_Previews: PreviewProvider {
    static var previews: some View {
        ChannelMemberList(mucContact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(3)));
    }
}
