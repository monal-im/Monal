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
    @State var isCalling = false
    var callController: CXCallController

    init(delegate: SheetDismisserProtocol, contact: ObservableKVOWrapper<MLContact>) {
        self.delegate = delegate
        _contact = StateObject(wrappedValue: contact)
        self.callController = CXCallController(queue: DispatchQueue.main)
    }

    var body: some View {
        ZStack {
            Color.white
            
            
        }
        .onAppear {
            DDLogDebug("Call UI appeared")
            let appDelegate = UIApplication.shared.delegate as! MonalAppDelegate
            if let voipProcessor = appDelegate.voipProcessor {
                if isCalling == false {
                    voipProcessor.initiateAudioCall(to:self.contact.obj)
                    isCalling = true
                }
            }
        }
        .onDisappear {
            DDLogDebug("Call UI disappeared")
        }
        .navigationBarTitle("Call with \(contact.contactDisplayName as String)", displayMode: .inline)
    }
}

struct AVPrototype_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        AVPrototype(delegate:delegate, contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(0)))
    }
}
