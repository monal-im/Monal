//
//  AVCallUI.swift
//  Monal
//
//  Created by Thilo Molitor on 20.12.22.
//  Copyright © 2021 Monal.im. All rights reserved.
//
import WebRTC
import AVFoundation
import CallKit
import AVKit
import monalxmpp

struct VideoView: UIViewRepresentable {
    var renderer: RTCMTLVideoView
 
    init(renderer: RTCMTLVideoView) {
        self.renderer = renderer
    }
    
    func makeUIView(context: Context) -> RTCMTLVideoView {
        return self.renderer
    }
 
    func updateUIView(_ renderer: RTCMTLVideoView, context: Context) {
        DDLogDebug("updateUIView called...")
        //do nothing
    }
}

struct AVCallUI: View {
    @StateObject private var appDelegate: ObservableKVOWrapper<MonalAppDelegate>
    @StateObject private var call: ObservableKVOWrapper<MLCall>
    @StateObject private var contact: ObservableKVOWrapper<MLContact>
    @State private var showMicAlert = false
    @State private var showSecurityHelpAlert: MLCallEncryptionState? = nil
    @State private var controlsVisible = true
    private var ringingPlayer: AVAudioPlayer!
    private var busyPlayer: AVAudioPlayer!
    private var errorPlayer: AVAudioPlayer!
    private var delegate: SheetDismisserProtocol
    private var formatter: DateComponentsFormatter
    private var localRenderer: RTCMTLVideoView
    private var remoteRenderer: RTCMTLVideoView

    init(delegate: SheetDismisserProtocol, call: MLCall) {
        _call = StateObject(wrappedValue: ObservableKVOWrapper(call))
        _contact = StateObject(wrappedValue: ObservableKVOWrapper(call.contact))
        _appDelegate = StateObject(wrappedValue: ObservableKVOWrapper(UIApplication.shared.delegate as! MonalAppDelegate))
        self.delegate = delegate
        self.formatter = DateComponentsFormatter()
        self.formatter.allowedUnits = [.hour, .minute, .second]
        self.formatter.unitsStyle = .positional
        self.formatter.zeroFormattingBehavior = .pad
        
        //use the complete screen for remote video
        self.remoteRenderer = RTCMTLVideoView(frame: UIScreen.main.bounds)
        self.remoteRenderer.videoContentMode = .scaleAspectFill
        
        self.localRenderer = RTCMTLVideoView(frame: UIScreen.main.bounds)
        self.localRenderer.videoContentMode = .scaleAspectFill
        self.localRenderer.transform = CGAffineTransformMakeScale(-1.0, 1.0)        //local video should be displayed as "mirrored"
        
        self.ringingPlayer = try! AVAudioPlayer(contentsOf:Bundle.main.url(forResource:"ringing", withExtension:"wav", subdirectory:"CallSounds")!)
        self.busyPlayer = try! AVAudioPlayer(contentsOf:Bundle.main.url(forResource:"busy", withExtension:"wav", subdirectory:"CallSounds")!)
        self.errorPlayer = try! AVAudioPlayer(contentsOf:Bundle.main.url(forResource:"error", withExtension:"wav", subdirectory:"CallSounds")!)
    }
    
    func maybeStartRenderer() {
        if MLCallType(rawValue:call.callType) == .video && MLCallState(rawValue:call.state) == .connected {
            DDLogError("Starting renderer...")
            call.obj.startCaptureLocalVideo(withRenderer: self.localRenderer)
            call.obj.renderRemoteVideo(withRenderer: self.remoteRenderer)
        }
    }
    
    func handleStateChange(_ state:MLCallState, _ audioState:MLAudioState) {
        switch state {
            case .unknown:
                DDLogDebug("state: unknown")
                ringingPlayer.stop()
                busyPlayer.stop()
                errorPlayer.play()
            case .discovering:
                DDLogDebug("state: discovering")
                ringingPlayer.stop()
                busyPlayer.stop()
                errorPlayer.stop()
            case .ringing:
                DDLogDebug("state: ringing")
                busyPlayer.stop()
                errorPlayer.stop()
                ringingPlayer.play()
            case .connecting:
                DDLogDebug("state: connecting")
                ringingPlayer.stop()
                busyPlayer.stop()
                errorPlayer.stop()
            case .reconnecting:
                DDLogDebug("state: reconnecting")
                ringingPlayer.stop()
                busyPlayer.stop()
                errorPlayer.stop()
            case .connected:
                DDLogDebug("state: connected")
                maybeStartRenderer()
                //we want our controls to disappear when we first connected, but want them to be visible when returning to a call
                //--> don't set controlsVisible to false in maybeStartRenderer(), but only here
                controlsVisible = false
            case .finished:
                DDLogDebug("state: finished: \(String(describing:call.finishReason as NSNumber))")
                //check audio state before trying to play anything (if we are still in state .call,
                //callkit will deactivate this audio session shortly, stopping our players)
                if audioState == .normal {
                    switch MLCallFinishReason(rawValue:call.finishReason) {
                        case .unknown:
                            DDLogDebug("state: finished: unknown")
                            ringingPlayer.stop()
                            busyPlayer.stop()
                            errorPlayer.stop()
                        case .connectivityError:
                            DDLogDebug("state: finished: connectivityError")
                            ringingPlayer.stop()
                            busyPlayer.stop()
                            errorPlayer.play()
                        case .securityError:
                            DDLogDebug("state: finished: securityError")
                            ringingPlayer.stop()
                            busyPlayer.stop()
                            errorPlayer.play()
                        case .unanswered:
                            DDLogDebug("state: finished: unanswered")
                            ringingPlayer.stop()
                            errorPlayer.stop()
                            busyPlayer.play()
                        case .retracted:
                            DDLogDebug("state: finished: retracted")
                            ringingPlayer.stop()
                            errorPlayer.stop()
                            busyPlayer.play()
                        case .rejected:
                            DDLogDebug("state: finished: rejected")
                            ringingPlayer.stop()
                            errorPlayer.stop()
                            busyPlayer.play()
                        case .declined:
                            DDLogDebug("state: finished: declined")
                            ringingPlayer.stop()
                            errorPlayer.stop()
                            busyPlayer.play()
                        case .error:
                            DDLogDebug("state: finished: error")
                            ringingPlayer.stop()
                            busyPlayer.stop()
                            errorPlayer.play()
//                             case .normal:
//                             case .answeredElsewhere:
                        default:
                            DDLogDebug("state: finished: default")
                            ringingPlayer.stop()
                            busyPlayer.stop()
                            errorPlayer.stop()
                    }
                }
            default:
                DDLogDebug("state: default")
        }
    }

    var body: some View {
        ZStack {
            Color.background
                .edgesIgnoringSafeArea(.all)
            
            if MLCallType(rawValue:call.callType) == .video && MLCallState(rawValue:call.state) == .connected {
                if MLCallState(rawValue:call.state) == .connected {
                    VideoView(renderer:self.remoteRenderer)
                }
                
                VStack {
                    Spacer().frame(height: 16)
                    
                    HStack {
                        Spacer()
                        
                        if MLCallState(rawValue:call.state) == .connected {
                            VideoView(renderer:self.localRenderer)
                                //this will sometimes only honor the width and ignore the height
                                .frame(width: UIScreen.main.bounds.size.width/5.0, height: UIScreen.main.bounds.size.height/5.0)
                        }
                        
                        Spacer().frame(width: 24)
                    }
                    
                    Spacer()
                }
            }
            
            if MLCallType(rawValue:call.callType) == .audio ||
            (MLCallType(rawValue:call.callType) == .video && (MLCallState(rawValue:call.state) != .connected || controlsVisible)) {
                VStack {
                    Group {
                        Spacer().frame(height: 24)
                        
                        HStack(alignment: .top) {
                            Spacer().frame(width:20)
                            
                            VStack {
                                Spacer().frame(height: 8)
                                switch MLCallDirection(rawValue:call.direction) {
                                    case .incoming:
                                        Image(systemName: "phone.arrow.down.left")
                                            .resizable()
                                            .frame(width: 20.0, height: 20.0)
                                            .foregroundColor(.primary)
                                    case .outgoing:
                                        Image(systemName: "phone.arrow.up.right")
                                            .resizable()
                                            .frame(width: 20.0, height: 20.0)
                                            .foregroundColor(.primary)
                                    default:        //should never be reached
                                        Text("")
                                }
                            }
                            
                            VStack {
                                Spacer().frame(height: 8)
                                Button(action: {
                                    //show dialog explaining different encryption states
                                    self.showSecurityHelpAlert = MLCallEncryptionState(rawValue:call.encryptionState)
                                }, label: {
                                    switch MLCallEncryptionState(rawValue:call.encryptionState) {
                                        case .unknown:
                                            Text("")
                                        case .clear:
                                            Spacer().frame(width: 10)
                                            Image(systemName: "xmark.shield.fill")
                                                .resizable()
                                                .frame(width: 20.0, height: 20.0)
                                                .foregroundColor(.red)
                                        case .toFU:
                                            Spacer().frame(width: 10)
                                            Image(systemName: "checkmark.shield.fill")
                                                .resizable()
                                                .frame(width: 20.0, height: 20.0)
                                                .foregroundColor(.yellow)
                                        case .trusted:
                                            Spacer().frame(width: 10)
                                            Image(systemName: "checkmark.shield.fill")
                                                .resizable()
                                                .frame(width: 20.0, height: 20.0)
                                                .foregroundColor(.green)
                                        default:        //should never be reached
                                            Text("")
                                    }
                                })
                            }
                            
                            Spacer()
                            
                            Text(contact.contactDisplayName as String)
                                .font(.largeTitle)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            VStack {
                                Spacer().frame(height: 8)
                                Button(action: {
                                    self.delegate.dismissWithoutAnimation()
                                    if let activeChats = self.appDelegate.obj.activeChats {
                                        activeChats.presentChat(with:self.contact.obj)
                                    }
                                }, label: {
                                    Image(systemName: "text.bubble")
                                        .resizable()
                                        .frame(width: 28.0, height: 28.0)
                                        .foregroundColor(.primary)
                                })
                            }
                            
                            Spacer().frame(width:20)
                        }
                        
                        Spacer().frame(height: 16)
                        
                        //this is needed because ObservableKVOWrapper somehow extracts an NSNumber? from it's wrapped object
                        //which results in a runtime error when trying to cast NSNumber? to MLCallState
                        switch MLCallState(rawValue:call.state) {
                            case .discovering:
                                Text("Discovering devices...")
                                .bold()
                                .foregroundColor(.primary)
                            case .ringing:
                                Text("Ringing...")
                                .bold()
                                .foregroundColor(.primary)
                            case .connecting:
                                Text("Connecting...")
                                .bold()
                                .foregroundColor(.primary)
                            case .reconnecting:
                                Text("Reconnecting...")
                                .bold()
                                .foregroundColor(.primary)
                            case .connected:
                                Text("Connected: \(formatter.string(from: TimeInterval(call.durationTime as UInt))!)")
                                .bold()
                                .foregroundColor(.primary)
                            case .finished:
                                switch MLCallFinishReason(rawValue:call.finishReason) {
                                    case .unknown:
                                        Text("Call ended for an unknown reason")
                                        .bold()
                                        .foregroundColor(.primary)
                                    case .normal:
                                        if call.wasConnectedOnce {
                                            Text("Call ended, duration: \(formatter.string(from: TimeInterval(call.durationTime as UInt))!)")
                                            .bold()
                                            .foregroundColor(.primary)
                                        } else {
                                            Text("Call ended")
                                            .bold()
                                            .foregroundColor(.primary)
                                        }
                                    case .connectivityError:
                                        if call.wasConnectedOnce {
                                            Text("Call ended: connection failed\nDuration: \(formatter.string(from: TimeInterval(call.durationTime as UInt))!)")
                                            .bold()
                                            .foregroundColor(.primary)
                                        } else {
                                            Text("Call ended: connection failed")
                                            .bold()
                                            .foregroundColor(.primary)
                                        }
                                    case .securityError:
                                        Text("Call ended: couldn't establish encryption")
                                        .bold()
                                        .foregroundColor(.primary)
                                    case .unanswered:
                                        Text("Call was not answered")
                                        .bold()
                                        .foregroundColor(.primary)
                                    case .answeredElsewhere:
                                        Text("Call ended: answered with other device")
                                        .bold()
                                        .foregroundColor(.primary)
                                    case .retracted:
                                        //this will only be displayed for timer-induced retractions,
                                        //reflect that in our text instead of using some generic "hung up"
                                        //Text("Call ended: hung up")
                                        Text("Call ended: remote busy")
                                        .bold()
                                        .foregroundColor(.primary)
                                    case .rejected:
                                        Text("Call ended: remote busy")
                                        .bold()
                                        .foregroundColor(.primary)
                                    case .declined:
                                        Text("Call ended: declined")
                                        .bold()
                                        .foregroundColor(.primary)
                                    case .error:
                                        Text("Call ended: application error")
                                        .bold()
                                        .foregroundColor(.primary)
                                    default:        //should never be reached
                                        Text("")
                                }
                            default:        //should never be reached
                                Text("")
                        }
                        
                        Spacer().frame(height: 48)
                        
                        if MLCallType(rawValue:call.callType) == .audio || MLCallState(rawValue:call.state) != .connected {
                            Image(uiImage: contact.avatar)
                                .resizable()
                                .frame(minWidth: 100, idealWidth: 150, maxWidth: 200, minHeight: 100, idealHeight: 150, maxHeight: 200, alignment: .center)
                                .scaledToFit()
                                .shadow(radius: 7)
                        }
                        
                        Spacer()
                    }
                    
                    if MLCallState(rawValue:call.state) == .finished {
                        HStack() {
                            Spacer()
                            
                            Button(action: {
                                self.delegate.dismissWithoutAnimation()
                                if let activeChats = self.appDelegate.obj.activeChats {
                                    activeChats.call(contact.obj)
                                }                            
                            }) {
                                if #available(iOS 15, *) {
                                    Image(systemName: "arrow.clockwise.circle.fill")
                                        .resizable()
                                        .frame(width: 64.0, height: 64.0)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .green)
                                        .shadow(radius: 7)
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
                                            .shadow(radius: 7)
                                    }
                                }
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            
                            Spacer().frame(width: 64)

                            Button(action: {
                                delegate.dismissWithoutAnimation()
                            }) {
                                if #available(iOS 15, *) {
                                    Image(systemName: "x.circle.fill")
                                        .resizable()
                                        .frame(width: 64.0, height: 64.0)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .red)
                                        .shadow(radius: 7)
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
                                            .shadow(radius: 7)
                                    }
                                }
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            
                            Spacer()
                        }
                    } else {
                        HStack() {
                            Spacer()
                            
                            if MLCallState(rawValue:call.state) == .connected || MLCallState(rawValue:call.state) == .reconnecting {
                                Button(action: {
                                    call.muted = !call.muted
                                }) {
                                    if #available(iOS 15, *) {
                                        Image(systemName: call.muted ? "mic.circle.fill" : "mic.slash.circle.fill")
                                            .resizable()
                                            .frame(width: 64.0, height: 64.0)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(call.muted ? .black : .white, call.muted ? .white : .black)
                                            .shadow(radius: 7)
                                    } else {
                                        ZStack {
                                            Image(systemName: "circle.fill")
                                                .resizable()
                                                .frame(width: 64.0, height: 64.0)
                                                .accentColor(call.muted ? .black : .white)
                                            Image(systemName: call.muted ? "mic.circle.fill" : "mic.circle.fill")
                                                .resizable()
                                                .frame(width: 64.0, height: 64.0)
                                                .accentColor(call.muted ? .white : .black)
                                                .shadow(radius: 7)
                                        }
                                    }
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                
                                Spacer().frame(width: 32)
                            }
                            
                            Button(action: {
                                call.obj.end()
                                self.delegate.dismissWithoutAnimation()
                            }) {
                                if #available(iOS 15, *) {
                                    Image(systemName: "phone.down.circle.fill")
                                        .resizable()
                                        .frame(width: 64.0, height: 64.0)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, .red)
                                        .shadow(radius: 7)
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
                                            .shadow(radius: 7)
                                    }
                                }
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            
                            if MLCallState(rawValue:call.state) == .connected || MLCallState(rawValue:call.state) == .reconnecting {
                                Spacer().frame(width: 32)
                                Button(action: {
                                    call.speaker = !call.speaker
                                }) {
                                    if #available(iOS 15, *) {
                                        Image(systemName: "speaker.wave.2.circle.fill")
                                            .resizable()
                                            .frame(width: 64.0, height: 64.0)
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(call.speaker ? .black : .white, call.speaker ? .white : .black)
                                            .shadow(radius: 7)
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
                                                .shadow(radius: 7)
                                        }
                                    }
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            
                            Spacer()
                        }
                    }
                    
                    Spacer().frame(height: 32)
                }
            }
        }
        .onTapGesture(count: 1) {
            controlsVisible = !controlsVisible
        }
        .alert(isPresented: $showMicAlert) {
            Alert(
                title: Text("Missing permission"),
                message: Text("You need to grant microphone access in iOS Settings-> Privacy-> Microphone, if you want that others can hear you."),
                dismissButton: .default(Text("OK"))
            )
        }
        .richAlert(isPresented:$showSecurityHelpAlert, title:Text("Call security help").foregroundColor(.black)) {
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: "xmark.shield.fill")
                        .resizable()
                        .frame(width: 20.0, height: 20.0)
                        .foregroundColor(.red)
                    Spacer().frame(width: 10)
                    Text("Red x-mark shield:")
                }.font(Font.body.weight(showSecurityHelpAlert == .clear ? .heavy : .medium))
                Text("This means your call is encrypted, but the remote party could not be verified using OMEMO encryption.\nYour or the callee's XMPP server could possibly Man-In-The-Middle you.")
                Spacer().frame(height: 20)
                
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .resizable()
                        .frame(width: 20.0, height: 20.0)
                        .foregroundColor(.yellow)
                    Spacer().frame(width: 10)
                    Text("Yellow checkmark shield:")
                }.font(Font.body.weight(showSecurityHelpAlert == .toFU ? .heavy : .medium))
                Text("This means your call is encrypted and the remote party was verified using OMEMO encryption.\nBut since you did not manually verify the callee's OMEMO fingerprints, your or the callee's XMPP server could possibly have inserted their own OMEMO keys to Man-In-The-Middle you.")
                Spacer().frame(height: 20)
                
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .resizable()
                        .frame(width: 20.0, height: 20.0)
                        .foregroundColor(.green)
                    Spacer().frame(width: 10)
                    Text("Green checkmark shield:")
                }.font(Font.body.weight(showSecurityHelpAlert == .trusted ? .heavy : .medium))
                Text("This means your call is encrypted and the remote party was verified using OMEMO encryption.\nYou manually verified the used OMEMO keys and no Man-In-The-Middle can take place.")
                Spacer().frame(height: 20)
            }.foregroundColor(.black)
        }
        .onAppear {
            //force portrait mode and lock ui there
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
            self.appDelegate.obj.orientationLock = .portrait
            UIApplication.shared.isIdleTimerDisabled = true
            
            self.ringingPlayer.numberOfLoops = -1
            self.busyPlayer.numberOfLoops = -1
            self.errorPlayer.numberOfLoops = -1
            
            //ask for mic permissions
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                if !granted {
                    showMicAlert = true
                }
            }
            
            maybeStartRenderer()
        }
        .onDisappear {
            //allow all orientations again
            self.appDelegate.obj.orientationLock = .all
            UIApplication.shared.isIdleTimerDisabled = false
            
            ringingPlayer.stop()
            busyPlayer.stop()
            errorPlayer.stop()
            
            call.obj.stopCaptureLocalVideo()
        }
        .onChange(of: MLCallState(rawValue:call.state)) { state in
            DDLogVerbose("call state changed: \(String(describing:call.state as NSNumber))")
            handleStateChange(call.obj.state, appDelegate.obj.audioState)
        }
        .onChange(of: MLAudioState(rawValue:appDelegate.audioState)) { audioState in
            DDLogVerbose("audioState changed: \(String(describing:appDelegate.audioState as NSNumber))")
            handleStateChange(call.obj.state, appDelegate.obj.audioState)
        }
    }
}

struct AVCallUI_Previews: PreviewProvider {
    static var delegate = SheetDismisserProtocol()
    static var previews: some View {
        AVCallUI(delegate:delegate, call:MLCall.makeDummyCall(0))
    }
}
