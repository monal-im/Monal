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
    var formatter: DateComponentsFormatter

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
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer().frame(height: 12)
                
                HStack {
                    Text(contact.contactDisplayName as String)
                        .font(.largeTitle)
                        .foregroundColor(.white)
                    
                    Spacer().frame(width: 20)
                    
                    Button(action: {
                        self.delegate.dismiss()
                    }, label: {
                        ZStack(alignment: .center) {
                                Image(systemName: "bubble.left.fill")
                                    .resizable()
                                    .frame(width: 28.0, height: 28.0)
                                    .foregroundColor(.white)
                                Image(systemName: "bubble.left")
                                    .resizable()
                                    .frame(width: 28.0, height: 28.0)
                                    .foregroundColor(.black)
                            if #available(iOS 16, *) {
                                Image(systemName: "return.left")
                                    .resizable()
                                    .frame(width: 10.0, height: 10.0)
                                    .foregroundColor(.black)
                                    .bold()
                                    .offset(y: -2)
                            } else {
                                Image(systemName: "return.left")
                                    .resizable()
                                    .frame(width: 10.0, height: 10.0)
                                    .foregroundColor(.black)
                                    .offset(y: -2)
                            }
                        }
                    })
                }
                
                Spacer().frame(height: 16)
                
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
                                .bold()
                            case .normal:
                                Text("Call ended, duration: \(formatter.string(from: TimeInterval(call.time as UInt))!)")
                            case .error:
                                Text("Call ended with error")
                                .bold()
                            case .unanswered:
                                Text("Call was not answered")
                                .bold()
                            case .rejected:
                                Text("Call ended: remote busy")
                                .bold()
                            default:        //should never be reached
                                Text("")
                        }
                    default:        //should never be reached
                        Text("")
                }
            
                Spacer().frame(height: 48)
                
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
                            let newCall = appDelegate.voipProcessor!.initiateAudioCall(to:contact.obj)
                            self.delegate.replace(with:AVPrototype(delegate: delegate, call: newCall))
                        }) {
                            if #available(iOS 15, *) {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .resizable()
                                    .frame(width: 64.0, height: 64.0)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .green)
                            } else {
                                ZStack {
                                    Image(systemName: "circle.fill")
                                        .resizable()
                                        .frame(width: 64.0, height: 64.0)
                                        .accentColor(.white)
                                    Image(systemName: "arrow.clockwise.circle.fill")
                                        .resizable()
                                        .frame(width: 64.0, height: 64.0)
                                        .accentColor(.green)
                                }
                            }
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        
                        Spacer().frame(width: 64)

                        Button(action: {
                            delegate.dismiss()
                        }) {
                            if #available(iOS 15, *) {
                                Image(systemName: "x.circle.fill")
                                    .resizable()
                                    .frame(width: 64.0, height: 64.0)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .red)
                            } else {
                                ZStack {
                                    Image(systemName: "circle.fill")
                                        .resizable()
                                        .frame(width: 64.0, height: 64.0)
                                        .accentColor(.white)
                                    Image(systemName: "x.circle.fill")
                                        .resizable()
                                        .frame(width: 64.0, height: 64.0)
                                        .accentColor(.red)
                                }
                            }
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
                            if #available(iOS 15, *) {
                                Image(systemName: call.muted ? "mic.circle.fill" : "mic.slash.circle.fill")
                                    .resizable()
                                    .frame(width: 64.0, height: 64.0)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(call.muted ? .white : .black, call.muted ? .black : .white)
                            } else {
                                ZStack {
                                    Image(systemName: "circle.fill")
                                        .resizable()
                                        .frame(width: 64.0, height: 64.0)
                                        .accentColor(call.muted ? .black : .white)
                                    Image(systemName: call.muted ? "mic.circle.fill" : "mic.slash.circle.fill")
                                        .resizable()
                                        .frame(width: 64.0, height: 64.0)
                                        .accentColor(call.muted ? .white : .black)
                                }
                            }
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        
                        Spacer().frame(width: 32)
                        Button(action: {
                            call.obj.end()
                            self.delegate.dismiss()
                        }) {
                            if #available(iOS 15, *) {
                                Image(systemName: "phone.down.circle.fill")
                                    .resizable()
                                    .frame(width: 64.0, height: 64.0)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .red)
                            } else {
                                ZStack(alignment: .center) {
                                    Image(systemName: "circle.fill")
                                        .resizable()
                                        .frame(width: 64.0, height: 64.0)
                                        .accentColor(.white)
                                    Image(systemName: "phone.down.circle.fill")
                                        .resizable()
                                        .frame(width: 64.0, height: 64.0)
                                        .accentColor(.red)
                                }
                            }
                        }
                        .buttonStyle(BorderlessButtonStyle())
                        
                        Spacer().frame(width: 32)
                        Button(action: {
                            call.speaker = !call.speaker
                        }) {
                            if #available(iOS 15, *) {
                                Image(systemName: "speaker.wave.2.circle.fill")
                                    .resizable()
                                    .frame(width: 64.0, height: 64.0)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(call.speaker ? .white : .black, call.speaker ? .black : .white)
                            } else {
                                ZStack {
                                    Image(systemName: "circle.fill")
                                        .resizable()
                                        .frame(width: 64.0, height: 64.0)
                                        .accentColor(call.speaker ? .black : .white)
                                    Image(systemName: "speaker.wave.2.circle.fill")
                                        .resizable()
                                        .frame(width: 64.0, height: 64.0)
                                        .accentColor(call.speaker ? .white : .black)
                                }
                            }
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
                    //delegate.dismiss()
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
