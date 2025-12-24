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
    @State private var ownRole: String;
    @StateObject var channel: ObservableKVOWrapper<MLContact>
    @State private var participants: OrderedDictionary<String, [String:String]>
    @StateObject private var overlay = LoadingOverlayState()

    init(mucContact: ObservableKVOWrapper<MLContact>) {
        account = mucContact.obj.account! as xmpp
        _channel = StateObject(wrappedValue:mucContact)
        _ownAffiliation = State(wrappedValue:kMucAffiliationNone)
        _ownRole = State(wrappedValue:kMucRoleNone)
        _participants = State(wrappedValue:OrderedDictionary<String, [String:String]>())
    }
    
    func updateParticipantList() {
        ownAffiliation = DataLayer.sharedInstance().getOwnAffiliation(inGroupOrChannel:channel.obj) ?? kMucAffiliationNone
        ownRole = DataLayer.sharedInstance().getOwnRole(inGroupOrChannel:channel.obj) ?? kMucRoleNone
        participants.removeAll(keepingCapacity:true)
        for memberInfo in Array(DataLayer.sharedInstance().getMembersAndParticipants(ofMuc:channel.contactJid, forAccountID:account.accountID)) {
            //ignore ourselves
            if let jid = memberInfo["participant_jid"] as? String ?? memberInfo["member_jid"] as? String {
                if jid == account.connectionProperties.identity.jid {
                    continue
                }
            }
            if let nick = memberInfo["room_nick"] as? String {
                participants[nick] = [
                    "affiliation": memberInfo["affiliation"] as? String ?? kMucAffiliationNone,
                    "role": memberInfo["role"] as? String ?? kMucRoleNone,
                ]
            }
        }
        participants.sort {
            (mucAffiliationToInt($0.value["affiliation"]), mucRoleToInt($0.value["role"]), $0.key.lowercased())
            <
            (mucAffiliationToInt($1.value["affiliation"]), mucRoleToInt($1.value["role"]), $1.key.lowercased())
        }
    }
    

    var body: some View {
        if ownRole == kMucRoleVisitor {
            HStack {
                Spacer().frame(width:20)
                Button("Request Voice") {
                    showPromisingLoadingOverlay(overlay, headline:"Requesting Voice") {
                        Guarantee { $0(account.mucProcessor.requestVoice(inMuc:channel.contactJid)) }
                    }
                }
                .foregroundStyle(Color.green)
                Spacer()
            }
        }
        List {
            Section(header: Text("\(self.channel.contactDisplayName as String) (affiliation: \(mucAffiliationToString(ownAffiliation, ownRole)))")) {
                ForEach(participants.keys, id: \.self) { participant_key in
                    ZStack(alignment: .topLeading) {
                        HStack(alignment: .center) {
                            Text(participant_key)
                            Spacer()
                            Text(mucAffiliationToString(participants[participant_key]?["affiliation"], participants[participant_key]?["role"]))
                        }
                    }
                }
            }
        }
        .addLoadingOverlay(overlay)
        .navigationBarTitle(Text("Channel Participants"), displayMode: .inline)
        .onAppear {
            updateParticipantList()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name(kMonalMucParticipantsAndMembersUpdated)).receive(on: RunLoop.main)) { notification in
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
