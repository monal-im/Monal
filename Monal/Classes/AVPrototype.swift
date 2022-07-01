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
    @State var state = "";
    var webRTCClient: WebRTCClient
    var webRTCDelegateHolder: WebRTCDelegate
    var callController: CXCallController

    init(contact: ObservableKVOWrapper<MLContact>) {
        _contact = StateObject(wrappedValue: contact)
        self.webRTCDelegateHolder = WebRTCDelegate(contact:contact)
        self.webRTCClient = WebRTCClient(iceServers: ["stun:stun.l.google.com:19302",
                                     "stun:stun1.l.google.com:19302",
                                     "stun:stun2.l.google.com:19302",
                                     "stun:stun3.l.google.com:19302",
                                     "stun:stun4.l.google.com:19302"])
        self.webRTCClient.delegate = self.webRTCDelegateHolder
        self.callController = CXCallController(queue: DispatchQueue.main)
    }

    var body: some View {
        VStack {
            Text(self.state)
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
                
                self.webRTCClient.offer { (sdp) in
                    DDLogInfo("Got local SDP offer...")
                    DDLogDebug("Offer: \(sdp)");
                    let account = MLXMPPManager.sharedInstance().getConnectedAccount(forID:self.contact.obj.accountId)
                    account?.sendSDP(sdp, to:self.contact.obj)
                }
            }
            Button("Answer Call") {
                self.webRTCClient.offer { (sdp) in
                    DDLogInfo("Sending local SDP answer...")
                    DDLogDebug("Answer: \(sdp)");
                    self.webRTCClient.answer { (localSdp) in
                        let account = MLXMPPManager.sharedInstance().getConnectedAccount(forID:self.contact.obj.accountId)
                        account?.sendSDP(localSdp, to:self.contact.obj)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalIncomingSDP")).receive(on: RunLoop.main)) { notification in
            if let account = notification.object as? xmpp, let sdp = notification.userInfo?["sdp"] as? RTCSessionDescription {
                self.state = "Got remote sdp offer"
                DDLogInfo("\(account): Got remote SDP: \(sdp)");
                self.webRTCClient.set(remoteSdp: sdp) { (error) in
                    if let error = error {
                        DDLogError("Got error while passing remote sdp to webRTCClient: \(error)")
                    } else {
                        DDLogDebug("Successfully passed SDP to webRTCClient...")
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalIncomingCandidate")).receive(on: RunLoop.main)) { notification in
            if let account = notification.object as? xmpp, let candidate = notification.userInfo?["candidate"] as? RTCIceCandidate {
                DDLogInfo("\(account): Got remote candidate: \(candidate)");
                self.webRTCClient.set(remoteCandidate: candidate) { error in
                    if let error = error {
                        DDLogError("Got error while passing new remote candidate to webRTCClient: \(error)")
                    } else {
                        DDLogDebug("Successfully passed new remote candidate to webRTCClient...")
                    }
                }
            }
        }
        
        .navigationBarTitle("AV Prototype (Audio only)", displayMode: .inline)
    }
}

class WebRTCDelegate: WebRTCClientDelegate {    
    var contact: ObservableKVOWrapper<MLContact>
    
    init(contact: ObservableKVOWrapper<MLContact>) {
        self.contact = contact
    }

    func webRTCClient(_ client: WebRTCClient, didDiscoverLocalCandidate candidate: RTCIceCandidate) {
        DDLogDebug("discovered local ICE candidate: \(candidate)")
        let account = MLXMPPManager.sharedInstance().getConnectedAccount(forID:self.contact.obj.accountId)
        account?.send(candidate, to:self.contact.obj)
    }
    
    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState) {
        switch state {
        case .connected, .completed:
            DDLogInfo("New WebRTC ICE state: connected")
        case .disconnected:
            DDLogInfo("New WebRTC ICE state: disconnected")
        case .failed, .closed:
            DDLogInfo("New WebRTC ICE state: closed")
        case .new:
            DDLogInfo("New WebRTC ICE state: new")
        case .checking:
            DDLogInfo("New WebRTC ICE state: checking")
        case .count:
            DDLogInfo("New WebRTC ICE state: count")
        @unknown default:
            DDLogInfo("New WebRTC ICE state: UNKNOWN")
        }
    }
    
    func webRTCClient(_ client: WebRTCClient, didReceiveData data: Data) {
        DDLogDebug("Received WebRTC data: \(data)")
        let message = String(data: data, encoding: .utf8) ?? "\(data)"
        DDLogInfo("Received decoded WebRTC data: \(message)")
    }
}

struct AVPrototype_Previews: PreviewProvider {
    static var previews: some View {
        AVPrototype(contact:ObservableKVOWrapper<MLContact>(MLContact.makeDummyContact(0)))
    }
}
