//
//  ConcurrencyCrashSmokeTests.swift
//  MonalTests
//
//  Created by Matthew Fennell on 10/11/2026.
//  Copyright © 2026 monal-im.org. All rights reserved.
//

@testable import Monal
import Testing

@MainActor
struct ConcurrencyCrashSmokeTests {

    let account = xmpp()
    let muc = "heath@chat.shakespeare.lit"
    let invitee = "hecate@shakespeare.lit"

    @Test("Can join a MUC without crashing")
    func canJoinMuc() {
        _ = AddContactMenu.join(muc: muc, from: account)
    }

    @Test("Can invite to a MUC without crashing")
    func canInviteToMuc() {
        _ = MemberList.invite(user: invitee, to: muc, from: account)
    }

    @Test("Can destroy a MUC without crashing")
    func canDestroyMuc() {
        _ = ContactDetails.destroy(muc: muc, from: account)
    }

}
