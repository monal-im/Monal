//
//  ChannelMemberList.swift
//  Monal
//
//  Created by Friedrich Altheide on 17.02.24.
//  Copyright © 2024 monal-im.org. All rights reserved.
//

struct ChannelMemberList: View {
    private let account: xmpp
    @State private var ownAffiliation: String;
    @State private var ownRole: String;
    @StateObject var channel: ObservableKVOWrapper<MLContact>
    @State private var participants: Array<[String: String]>

    init(mucContact: ObservableKVOWrapper<MLContact>) {
        account = mucContact.obj.account! as xmpp
        _channel = StateObject(wrappedValue:mucContact)
        _ownAffiliation = State(wrappedValue:kMucAffiliationNone)
        _ownRole = State(wrappedValue:kMucRoleNone)
        _participants = State(wrappedValue:Array<[String: String]>())
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
                let affiliation = memberInfo["affiliation"] as? String ?? kMucAffiliationNone
                let role = memberInfo["role"] as? String ?? kMucRoleNone
                let occupantId = memberInfo["occupant_id"] as? String ?? ""
                participants.append([
                    "nick": nick,
                    "affiliation": affiliation,
                    "role": role,
                    "occupantId": occupantId
                ])
            }
        }
        participants.sort {
            (mucAffiliationToInt($0["affiliation"]), mucRoleToInt($0["role"]), $0["nick"]!.lowercased())
            <
            (mucAffiliationToInt($1["affiliation"]), mucRoleToInt($1["role"]), $1["nick"]!.lowercased())
        }
    }
    

    var body: some View {
        List {
            Section(header: Text("\(self.channel.contactDisplayName as String) (affiliation: \(mucAffiliationToString(ownAffiliation, ownRole)))")) {
                ForEach(participants, id: \.self) { participant in
                    ZStack(alignment: .topLeading) {
                        HStack(alignment: .center) {
                            Image(uiImage: MLImageManager.sharedInstance().getAvatarForOccupant(participant["occupantId"], inRoom: channel.contactJid, havingNick: participant["nick"]!, forAccount: account.accountID))
                                .resizable()
                                .frame(width: 35, height: 35, alignment: .center)
                                .padding(.vertical, 1)
                                .padding(.trailing, 8)
                            Text(participant["nick"]!)
                            Spacer()
                            Text(mucAffiliationToString(participant["affiliation"], participant["role"]))
                        }
                    }
                }
            }
        }
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
