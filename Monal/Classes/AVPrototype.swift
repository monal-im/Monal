//
//  ContactResources.swift
//  Monal
//
//  Created by Friedrich Altheide on 24.12.21.
//  Copyright © 2021 Monal.im. All rights reserved.
//
import monalxmpp

import SwiftUI
import CocoaLumberjack
import WebRTC
import AVFoundation
import CallKit

struct AVPrototype: View {
    @StateObject var contact: ObservableKVOWrapper<MLContact>
    var callController: CXCallController

    init(contact: ObservableKVOWrapper<MLContact>) {
        _contact = StateObject(wrappedValue: contact)
        self.callController = CXCallController(queue: DispatchQueue.main)
    }

    var body: some View {
        VStack {
            Button("Start Call") {
                let uuid = UUID()
                let handle = CXHandle(type:.emailAddress, value:self.contact.obj.contactJid)
                let startCallAction = CXStartCallAction(call: uuid, handle: handle)
                let transaction = CXTransaction(action: startCallAction)
                self.callController.request(transaction) { error in
                    if let error = error {
                        print("Error requesting transaction: \(error)")
                    } else {
                        print("Requested transaction successfully")
                    }
                }
                
//                 self.webRTCClient.offer { (sdp) in
//                     DDLogInfo("Got local SDP offer...")
//                     DDLogDebug("Offer: \(sdp)");
//                 }
            }
        }
        .navigationBarTitle("AV Prototype (Audio only)", displayMode: .inline)
    }
}

struct AVPrototype_Previews: PreviewProvider {
    static var previews: some View {
        AVPrototype(contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(0)))
    }
}
