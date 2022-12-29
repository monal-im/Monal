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
    var delegate: SheetDismisserProtocol
    @StateObject var contact: ObservableKVOWrapper<MLContact>
    var callController: CXCallController

    init(delegate: SheetDismisserProtocol, contact: ObservableKVOWrapper<MLContact>) {
        self.delegate = delegate
        _contact = StateObject(wrappedValue: contact)
        self.callController = CXCallController(queue: DispatchQueue.main)
    }

    var body: some View {
        VStack {
            Button("Start Call") {
                let appDelegate = UIApplication.shared.delegate as! MonalAppDelegate
                if let voipProcessor = appDelegate.voipProcessor {
                    voipProcessor.initiateAudioCall(to:self.contact.obj)
                }
            }
        }
        .navigationBarTitle("AV Prototype (Audio only)", displayMode: .inline)
    }
}

struct AVPrototype_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        AVPrototype(delegate:delegate, contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(0)))
    }
}
