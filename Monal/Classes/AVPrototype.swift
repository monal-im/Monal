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
    @StateObject var call: ObservableKVOWrapper<MLCall>
    @StateObject var contact: ObservableKVOWrapper<MLContact>
    var formatter: DateComponentsFormatter;

    init(delegate: SheetDismisserProtocol, call: MLCall) {
        self.delegate = delegate
        _call = StateObject(wrappedValue: ObservableKVOWrapper(call))
        _contact = StateObject(wrappedValue: ObservableKVOWrapper(call.contact))
        self.formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
    }

    var body: some View {
        ZStack {
            monalGreen
            
            VStack {
                Spacer().frame(height: 32)
                
                Text(contact.contactDisplayName as String)
                    .font(.largeTitle)
                
                Spacer().frame(height: 12)
                
                //this is needed because ObservableKVOWrapper somehow extracts an NSNumber from it's wrapped object
                //which results in a runtime error when trying to cast NSNumber? to MLCallState
                switch MLCallState(rawValue:(call.state as NSNumber).uintValue) {
                    case .ringing:
                        Text("Ringing...")
                    case .connecting:
                        Text("Connecting...")
                    case .connected:
                        Text("Connected: \(formatter.string(from: TimeInterval(call.time as UInt))!)")
                    case .finished:
                        switch MLCallFinishReason(rawValue:(call.finishReason as NSNumber).uintValue) {
                            case .unknown:
                                Text("Call ended for an unknown reason")
                            case .normal:
                                Text("Call ended normally")
                            case .error:
                                Text("Call ended with error")
                            case .unanswered:
                                Text("Call was not answered")
                            case .rejected:
                                Text("Call ended: remote busy")
                            default:
                                Text("Call ended")      //should never be reached
                        }
                    case .idle:
                        Text("Idle state")
                    default:
                        Text("Unknown state")           //should never be reached
                }
            
                Spacer().frame(height: 32)
                
                Image(uiImage: contact.avatar)
                    .resizable()
                    .frame(minWidth: 100, idealWidth: 150, maxWidth: 200, minHeight: 100, idealHeight: 150, maxHeight: 200, alignment: .center)
                    .scaledToFit()
                    .shadow(radius: 7)
                
                Spacer()
                
                if MLCallState(rawValue:(call.state as NSNumber).uintValue) == .finished {
                    HStack() {
                        Spacer()
                        
                        Button(action: {
                            let appDelegate = UIApplication.shared.delegate as! MonalAppDelegate
                            appDelegate.voipProcessor!.initiateAudioCall(to:contact.obj)
                        }) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .resizable()
                                .frame(width: 64.0, height: 64.0)
                                .accentColor(.green)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        
                        Spacer().frame(width: 64)

                        Button(action: {
                            self.delegate.dismiss()
                        }) {
                            Image(systemName: "x.circle.fill")
                                .resizable()
                                .frame(width: 64.0, height: 64.0)
                                .accentColor(.red)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        
                        Spacer()
                    }
                } else {
                    HStack() {
                        Spacer()
                        
                        Button(action: {
                            call.muted = !call.muted
                        }) {
                            Image(systemName: call.muted ? "mic.circle.fill" : "mic.slash.circle.fill")
                                .resizable()
                                .frame(width: 64.0, height: 64.0)
                                .accentColor(call.muted ? .white : .black)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        
                        Spacer().frame(width: 32)
                        Button(action: {
                            call.obj.end()
                        }) {
                            Image(systemName: "phone.down.circle.fill")
                                .resizable()
                                .frame(width: 64.0, height: 64.0)
                                .accentColor(.red)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        
                        Spacer().frame(width: 32)
                        Button(action: {
                            call.speaker = !call.speaker
                        }) {
                            Image(systemName: "speaker.wave.2.circle.fill")
                                .resizable()
                                .frame(width: 64.0, height: 64.0)
                                .accentColor(call.speaker ? .white : .black)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        
                        Spacer()
                    }
                }
                
                Spacer().frame(height: 32)
            }
        }
        .navigationBarTitle("Call with \(contact.contactDisplayName as String)", displayMode: .inline)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("kMonalCallRemoved")).receive(on: RunLoop.main)) { notification in
            if let notificationCall = notification.object as? MLCall {
                if notificationCall == call.obj {
                    //self.delegate.dismiss()
                }
            }
        }
    }
}

struct AVPrototype_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        AVPrototype(delegate:delegate, call:MLCall.makeDummyCall(0))
    }
}
