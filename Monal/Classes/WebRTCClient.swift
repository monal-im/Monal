//
//  WebRTCClient.swift
//  WebRTC
//
//  Created by Stasel on 20/05/2018.
//  Copyright © 2018 Stasel. All rights reserved.
//  Copyright © 2022 Thilo Molitor. All rights reserved.
//

import WebRTC

@objc
protocol WebRTCClientDelegate: AnyObject {
    func webRTCClient(_ client: WebRTCClient, didDiscoverLocalCandidate candidate: RTCIceCandidate)
    func webRTCClient(_ client: WebRTCClient, didChangeConnectionState state: RTCIceConnectionState)
    func webRTCClient(_ client: WebRTCClient, didReceiveData data: Data)
}

@objc
final class WebRTCClient: NSObject {
    
    // The `RTCPeerConnectionFactory` is in charge of creating new RTCPeerConnection instances.
    // A new RTCPeerConnection should be created every new call, but the factory is shared.
    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: videoEncoderFactory, decoderFactory: videoDecoderFactory)
    }()
    
    @objc var delegate: WebRTCClientDelegate?
    @objc public let peerConnection: RTCPeerConnection
    private let rtcAudioSession =  RTCAudioSession.sharedInstance()
    private let audioQueue = DispatchQueue(label: "audio")
    private let streamId = "stream"
    private var mediaConstrains: [String:String] = [:]
    private var videoCapturer: RTCVideoCapturer?
    private var localVideoTrack: RTCVideoTrack?
    private var remoteVideoTrack: RTCVideoTrack?
    private var localDataChannel: RTCDataChannel?
    private var remoteDataChannel: RTCDataChannel?

    @available(*, unavailable)
    override init() {
        unreachable("WebRTCClient:init is unavailable")
    }
    
    deinit {
        DDLogDebug("Deinit of webrtc client for delegate: \(String(describing:self.delegate))")
    }
    
    @objc
    static func createPeerConnection(iceServers: [RTCIceServer], forceRelay: Bool) -> RTCPeerConnection? {
        let config = RTCConfiguration()
        if forceRelay {
            config.iceTransportPolicy = .relay
        } else {
            config.iceTransportPolicy = .all
        }
        config.iceServers = iceServers
        
        // Unified plan is more superior than planB
        config.sdpSemantics = .unifiedPlan
        
        // gatherContinually will let WebRTC to listen to any network changes and send any new candidates to the other client
        config.continualGatheringPolicy = .gatherContinually
        
        //config.tcpCandidatePolicy = .disabled       // XEP-0176 doesn't support tcp
        config.rtcpMuxPolicy = .negotiate
        
        //aggressive pings to detect wifi - mobile handoffs better
        config.iceConnectionReceivingTimeout = 1000
        config.iceBackupCandidatePairPingInterval = 2000
        
        //bigger jitter buffer for better audio quality (2s, default: 1s)
        config.audioJitterBufferMaxPackets = 100;
        
        // Define media constraints. DtlsSrtpKeyAgreement is required to be true to be able to connect with web browsers.
        let constraints = RTCMediaConstraints(mandatoryConstraints: [
            "DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue
        ], optionalConstraints: [
            "echoCancellation": kRTCMediaConstraintsValueTrue,
            "noiseSuppression": kRTCMediaConstraintsValueTrue,
            "VoiceActivityDetection": kRTCMediaConstraintsValueTrue
        ])
        
        DDLogInfo("iceConnectionReceivingTimeout=\(config.iceConnectionReceivingTimeout), iceBackupCandidatePairPingInterval=\(config.iceBackupCandidatePairPingInterval)");
        return WebRTCClient.factory.peerConnection(with: config, constraints: constraints, delegate: nil)
    }
    
    @objc
    required init(iceServers: [RTCIceServer], audioOnly: Bool, forceRelay: Bool) {
        RTCSetMinDebugLogLevel(.info)
        
        var peerConnection = WebRTCClient.createPeerConnection(iceServers: iceServers, forceRelay: forceRelay)
        if peerConnection == nil {
            // try again with empty ice server list
            DDLogError("Broken ice server list, retrying without any ice servers: \(String(describing:iceServers))")
            peerConnection = WebRTCClient.createPeerConnection(iceServers: [], forceRelay: forceRelay)
            guard peerConnection != nil else {
                //this should never happen --> crash
                unreachable("Could not create new RTCPeerConnection")
            }
        }
        
        self.peerConnection = peerConnection!
        super.init()
        
        self.createMediaSenders(audioOnly: audioOnly)
        self.peerConnection.delegate = self
        
        if audioOnly {
            self.mediaConstrains = [
                kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueFalse,
            ]
        } else {
            self.mediaConstrains = [
                kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue,
            ]
        }
    }
    
    // MARK: Signaling
    @objc
    func offer(completion: @escaping (_ sdp: RTCSessionDescription) -> Void) {
        let constrains = RTCMediaConstraints(mandatoryConstraints: self.mediaConstrains,
                                             optionalConstraints: nil)
        self.peerConnection.offer(for: constrains) { (sdp, error) in
            guard let sdp = sdp else {
                return
            }
            
            self.peerConnection.setLocalDescription(sdp, completionHandler: { (error) in
                completion(sdp)
            })
        }
    }
    
    @objc
    func answer(completion: @escaping (_ sdp: RTCSessionDescription) -> Void)  {
        let constrains = RTCMediaConstraints(mandatoryConstraints: self.mediaConstrains,
                                             optionalConstraints: nil)
        self.peerConnection.answer(for: constrains) { (sdp, error) in
            guard let sdp = sdp else {
                return
            }
            
            self.peerConnection.setLocalDescription(sdp, completionHandler: { (error) in
                completion(sdp)
            })
        }
    }
    
    @objc
    func setRemoteSdp(_ remoteSdp: RTCSessionDescription, completion: @escaping (Error?) -> ()) {
        self.peerConnection.setRemoteDescription(remoteSdp, completionHandler: completion)
    }
    
    @objc
    func setRemoteCandidate(_ remoteCandidate : RTCIceCandidate, completion: @escaping (Error?) -> ()) {
        self.peerConnection.add(remoteCandidate, completionHandler: completion)
    }
    
    // MARK: Media
    @objc
    func startCaptureLocalVideo(renderer: RTCVideoRenderer, andCameraPosition position: AVCaptureDevice.Position) {
        guard let capturer = self.videoCapturer as? RTCCameraVideoCapturer else {
            return
        }
        
        guard
            let frontCamera = (RTCCameraVideoCapturer.captureDevices().first { $0.position == position }),
        
            // choose highest res
            let format = (RTCCameraVideoCapturer.supportedFormats(for: frontCamera).sorted { (f1, f2) -> Bool in
                let width1 = CMVideoFormatDescriptionGetDimensions(f1.formatDescription).width
                let width2 = CMVideoFormatDescriptionGetDimensions(f2.formatDescription).width
                return width1 < width2
            }).last,
        
            // choose highest fps
            let fps = (format.videoSupportedFrameRateRanges.sorted { return $0.maxFrameRate < $1.maxFrameRate }.last) else {
            return
        }

        capturer.startCapture(with: frontCamera,
                              format: format,
                              fps: Int(fps.maxFrameRate))
        
        self.localVideoTrack?.add(renderer)
    }
    
    @objc
    func stopCaptureLocalVideo() {
        guard let capturer = self.videoCapturer as? RTCCameraVideoCapturer else {
            return
        }
        capturer.stopCapture()
    }
    
    @objc
    func renderRemoteVideo(to renderer: RTCVideoRenderer) {
        self.remoteVideoTrack?.add(renderer)
    }
    
    @objc
    func addVideo() {
        let videoTrack = self.createVideoTrack()
        self.localVideoTrack = videoTrack
        self.peerConnection.add(videoTrack, streamIds: [self.streamId])
        self.remoteVideoTrack = self.peerConnection.transceivers.first { $0.mediaType == .video }?.receiver.track as? RTCVideoTrack
    }
    
    @objc
    func configureAudioSession() {
        DDLogInfo("Configuring shared rtcAudioSession...")
        self.rtcAudioSession.lockForConfiguration()
        do {
            try self.rtcAudioSession.setCategory(AVAudioSession.Category.playAndRecord)
            try self.rtcAudioSession.setMode(AVAudioSession.Mode.voiceChat)
        } catch let error {
            DDLogDebug("Error changeing AVAudioSession category: \(error)")
        }
        self.rtcAudioSession.useManualAudio = true
        self.rtcAudioSession.isAudioEnabled = false
        self.rtcAudioSession.unlockForConfiguration()
    }
    
    private func createMediaSenders(audioOnly: Bool) {
        //Audio
        let audioTrack = self.createAudioTrack()
        self.peerConnection.add(audioTrack, streamIds: [self.streamId])
        
        //Video
        if !audioOnly {
            // see https://stackoverflow.com/a/43765394
            self.addVideo()
        }
        
        //we don't use any data channels for A/V calls
//         // Data
//         if let dataChannel = createDataChannel() {
//             dataChannel.delegate = self
//             self.localDataChannel = dataChannel
//         }
    }
    
    private func createAudioTrack() -> RTCAudioTrack {
        let audioConstrains = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let audioSource = WebRTCClient.factory.audioSource(with: audioConstrains)
        let audioTrack = WebRTCClient.factory.audioTrack(with: audioSource, trackId: "audio0")
        return audioTrack
    }
    
    private func createVideoTrack() -> RTCVideoTrack {
        let videoSource = WebRTCClient.factory.videoSource()
        
        #if targetEnvironment(simulator)
        self.videoCapturer = RTCFileVideoCapturer(delegate: videoSource)
        #else
        self.videoCapturer = RTCCameraVideoCapturer(delegate: videoSource)
        #endif
        
        //see https://bugs.chromium.org/p/webrtc/issues/detail?id=10006#c2
        let aClass: AnyClass! = object_getClass(self.videoCapturer!)
        let bClass: AnyClass! = object_getClass(self)
        if self.videoCapturer!.responds(to: NSSelectorFromString("updateOrientation")) {
            DDLogWarn("Swizzling method 'updateOrientation' of video capturer...")
            let swizzledMethod = class_getInstanceMethod(aClass, NSSelectorFromString("updateOrientation"))
            let replacementMethod = class_getInstanceMethod(bClass, NSSelectorFromString("dummyUpdateOrientation"))
            let replacementImplementation = method_getImplementation(replacementMethod!)
            method_setImplementation(swizzledMethod!, replacementImplementation)
        }
        
        let videoTrack = WebRTCClient.factory.videoTrack(with: videoSource, trackId: "video0")
        return videoTrack
    }
    
    @objc
    func dummyUpdateOrientation() {
        DDLogDebug("Ignoring device orientation change in webrtc...")
    }
    
    // MARK: Data Channels
    private func createDataChannel() -> RTCDataChannel? {
        let config = RTCDataChannelConfiguration()
        guard let dataChannel = self.peerConnection.dataChannel(forLabel: "WebRTCData", configuration: config) else {
            DDLogDebug("Warning: Couldn't create data channel.")
            return nil
        }
        return dataChannel
    }
    
    @objc
    func sendData(_ data: Data) {
        let buffer = RTCDataBuffer(data: data, isBinary: true)
        self.remoteDataChannel?.sendData(buffer)
    }
}

extension WebRTCClient: RTCPeerConnectionDelegate {
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        DDLogDebug("peerConnection new signaling state: \(stateChanged)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        DDLogDebug("peerConnection did add stream")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        DDLogDebug("peerConnection did remove stream")
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        DDLogDebug("peerConnection should negotiate")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        DDLogDebug("peerConnection new connection state: \(newState)")
        self.delegate?.webRTCClient(self, didChangeConnectionState: newState)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        DDLogDebug("peerConnection new gathering state: \(newState)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        self.delegate?.webRTCClient(self, didDiscoverLocalCandidate: candidate)
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        DDLogDebug("peerConnection did remove candidate(s)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        DDLogDebug("peerConnection did open data channel")
        self.remoteDataChannel = dataChannel
    }
}
extension WebRTCClient {
    private func setTrackEnabled<T: RTCMediaStreamTrack>(_ type: T.Type, isEnabled: Bool) {
        peerConnection.transceivers
            .compactMap { return $0.sender.track as? T }
            .forEach { $0.isEnabled = isEnabled }
    }
}

// MARK: - Video control
extension WebRTCClient {
    @objc
    func hideVideo() {
        self.setVideoEnabled(false)
    }
    @objc
    func showVideo() {
        self.setVideoEnabled(true)
    }
    private func setVideoEnabled(_ isEnabled: Bool) {
        setTrackEnabled(RTCVideoTrack.self, isEnabled: isEnabled)
    }
}
// MARK:- Audio control
extension WebRTCClient {
    @objc
    func muteAudio() {
        self.setAudioEnabled(false)
    }
    
    @objc
    func unmuteAudio() {
        self.setAudioEnabled(true)
    }
    
    // Fallback to the default playing device: headphones/bluetooth/ear speaker
    @objc
    func speakerOff() {
        self.audioQueue.async { [weak self] in
            guard let self = self else {
                return
            }
            
            self.rtcAudioSession.lockForConfiguration()
            do {
                try self.rtcAudioSession.setCategory(AVAudioSession.Category.playAndRecord)
                try self.rtcAudioSession.overrideOutputAudioPort(.none)
            } catch let error {
                DDLogDebug("Error setting AVAudioSession category: \(error)")
            }
            self.rtcAudioSession.unlockForConfiguration()
        }
    }
    
    // Force speaker
    @objc
    func speakerOn() {
        self.audioQueue.async { [weak self] in
            guard let self = self else {
                return
            }
            
            self.rtcAudioSession.lockForConfiguration()
            do {
                try self.rtcAudioSession.setCategory(AVAudioSession.Category.playAndRecord)
                try self.rtcAudioSession.overrideOutputAudioPort(.speaker)
                try self.rtcAudioSession.setActive(true)
            } catch let error {
                DDLogDebug("Couldn't force audio to speaker: \(error)")
            }
            self.rtcAudioSession.unlockForConfiguration()
        }
    }
    
    private func setAudioEnabled(_ isEnabled: Bool) {
        setTrackEnabled(RTCAudioTrack.self, isEnabled: isEnabled)
    }
}

extension WebRTCClient: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        DDLogDebug("dataChannel did change state: \(dataChannel.readyState)")
    }
    
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        self.delegate?.webRTCClient(self, didReceiveData: buffer.data)
    }
}
