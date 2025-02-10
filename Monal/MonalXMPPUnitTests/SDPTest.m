//
//  SDPTest.m
//  MonalXMPPUnitTests
//
//  Created by admin on 10.02.25.
//  Copyright © 2025 monal-im.org. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import <monalxmpp/MLConstants.h>
#import <monalxmpp/monalxmpp-Swift.h>
#import <monalxmpp/HelperTools.h>
#import <monalxmpp/MLXMLNode.h>

static NSString* _rawSDPString = @"v=0\n\
o=- 2005859539484728435 2 IN IP4 127.0.0.1\n\
s=-\n\
t=0 0\n\
a=group:BUNDLE 0 1 2\n\
a=extmap-allow-mixed\n\
a=msid-semantic: WMS stream\n\
m=audio 9 UDP/TLS/RTP/SAVPF 111 63 9 102 0 8 13 110 126\n\
c=IN IP4 0.0.0.0\n\
a=candidate:1076231993 2 udp 41885694 198.51.100.52 50002 typ relay raddr 0.0.0.0 rport 0 generation 0 ufrag V4as network-id 2 network-cost 10\n\
a=rtcp:9 IN IP4 0.0.0.0\n\
a=ice-ufrag:Pt2c\n\
a=ice-pwd:XKe021opw+vupIkkLCI1+kP4\n\
a=ice-options:trickle renomination\n\
a=fingerprint:sha-256 1F:CE:47:40:5F:F2:FC:66:F2:21:F7:7D:3D:D6:0D:B0:67:6F:BD:CF:8B:0E:B7:90:5D:8C:33:9E:AD:F2:CB:FC\n\
a=setup:actpass\n\
a=mid:0\n\
a=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level\n\
a=extmap:2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\n\
a=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\n\
a=extmap:4 urn:ietf:params:rtp-hdrext:sdes:mid\n\
a=sendrecv\n\
a=msid:stream audio0\n\
a=rtcp-mux\n\
a=rtpmap:111 opus/48000/2\n\
a=rtcp-fb:111 transport-cc\n\
a=fmtp:111 minptime=10;useinbandfec=1\n\
a=rtpmap:63 red/48000/2\n\
a=fmtp:63 111/111\n\
a=rtpmap:9 G722/8000\n\
a=rtpmap:102 ILBC/8000\n\
a=rtpmap:0 PCMU/8000\n\
a=rtpmap:8 PCMA/8000\n\
a=rtpmap:13 CN/8000\n\
a=rtpmap:110 telephone-event/48000\n\
a=rtpmap:126 telephone-event/8000\n\
a=ssrc:109112503 cname:vUpPwDICjVuwEwGO\n\
a=ssrc:109112503 msid:stream audio0\n\
m=video 9 UDP/TLS/RTP/SAVPF 96 97 98 99 100 101 127 103 35 36 104 105 106\n\
c=IN IP4 0.0.0.0\n\
a=rtcp:9 IN IP4 0.0.0.0\n\
a=ice-ufrag:Pt2c\n\
a=ice-pwd:XKe021opw+vupIkkLCI1+kP4\n\
a=ice-options:trickle renomination\n\
a=fingerprint:sha-256 1F:CE:47:40:5F:F2:FC:66:F2:21:F7:7D:3D:D6:0D:B0:67:6F:BD:CF:8B:0E:B7:90:5D:8C:33:9E:AD:F2:CB:FC\n\
a=setup:actpass\n\
a=mid:1\n\
a=extmap:14 urn:ietf:params:rtp-hdrext:toffset\n\
a=extmap:2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\n\
a=extmap:13 urn:3gpp:video-orientation\n\
a=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\n\
a=extmap:5 http://www.webrtc.org/experiments/rtp-hdrext/playout-delay\n\
a=extmap:6 http://www.webrtc.org/experiments/rtp-hdrext/video-content-type\n\
a=extmap:7 http://www.webrtc.org/experiments/rtp-hdrext/video-timing\n\
a=extmap:8 http://www.webrtc.org/experiments/rtp-hdrext/color-space\n\
a=extmap:4 urn:ietf:params:rtp-hdrext:sdes:mid\n\
a=extmap:10 urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id\n\
a=extmap:11 urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id\n\
a=sendrecv\n\
a=msid:stream video0\n\
a=rtcp-mux\n\
a=rtcp-rsize\n\
a=rtpmap:96 H264/90000\n\
a=rtcp-fb:96 goog-remb\n\
a=rtcp-fb:96 transport-cc\n\
a=rtcp-fb:96 ccm fir\n\
a=rtcp-fb:96 nack\n\
a=rtcp-fb:96 nack pli\n\
a=fmtp:96 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=640c34\n\
a=rtpmap:97 rtx/90000\n\
a=fmtp:97 apt=96\n\
a=rtpmap:98 H264/90000\n\
a=rtcp-fb:98 goog-remb\n\
a=rtcp-fb:98 transport-cc\n\
a=rtcp-fb:98 ccm fir\n\
a=rtcp-fb:98 nack\n\
a=rtcp-fb:98 nack pli\n\
a=fmtp:98 level-asymmetry-allowed=1;packetization-mode=1;profile-level-id=42e034\n\
a=rtpmap:99 rtx/90000\n\
a=fmtp:99 apt=98\n\
a=rtpmap:100 VP8/90000\n\
a=rtcp-fb:100 goog-remb\n\
a=rtcp-fb:100 transport-cc\n\
a=rtcp-fb:100 ccm fir\n\
a=rtcp-fb:100 nack\n\
a=rtcp-fb:100 nack pli\n\
a=rtpmap:101 rtx/90000\n\
a=fmtp:101 apt=100\n\
a=rtpmap:127 VP9/90000\n\
a=rtcp-fb:127 goog-remb\n\
a=rtcp-fb:127 transport-cc\n\
a=rtcp-fb:127 ccm fir\n\
a=rtcp-fb:127 nack\n\
a=rtcp-fb:127 nack pli\n\
a=rtpmap:103 rtx/90000\n\
a=fmtp:103 apt=127\n\
a=rtpmap:35 AV1/90000\n\
a=rtcp-fb:35 goog-remb\n\
a=rtcp-fb:35 transport-cc\n\
a=rtcp-fb:35 ccm fir\n\
a=rtcp-fb:35 nack\n\
a=rtcp-fb:35 nack pli\n\
a=rtpmap:36 rtx/90000\n\
a=fmtp:36 apt=35\n\
a=rtpmap:104 red/90000\n\
a=rtpmap:105 rtx/90000\n\
a=fmtp:105 apt=104\n\
a=rtpmap:106 ulpfec/90000\n\
a=ssrc-group:FID 3733210709 4025710505\n\
a=ssrc:3733210709 cname:vUpPwDICjVuwEwGO\n\
a=ssrc:3733210709 msid:stream video0\n\
a=ssrc:4025710505 cname:vUpPwDICjVuwEwGO\n\
a=ssrc:4025710505 msid:stream video0\n\
m=application 9 UDP/DTLS/SCTP webrtc-datachannel\n\
c=IN IP4 0.0.0.0\n\
a=ice-ufrag:Pt2c\n\
a=ice-pwd:XKe021opw+vupIkkLCI1+kP4\n\
a=ice-options:trickle renomination\n\
a=fingerprint:sha-256 1F:CE:47:40:5F:F2:FC:66:F2:21:F7:7D:3D:D6:0D:B0:67:6F:BD:CF:8B:0E:B7:90:5D:8C:33:9E:AD:F2:CB:FC\n\
a=setup:actpass\n\
a=mid:2\n\
a=sctp-port:5000\n\
a=max-message-size:262144\n";

static NSString* _rawXMLString = @"<root><group xmlns=\"urn:xmpp:jingle:apps:grouping:0\" semantics=\"BUNDLE\"><content name=\"0\"/><content name=\"1\"/><content name=\"2\"/></group><content xmlns=\"urn:xmpp:jingle:1\" creator=\"initiator\" senders=\"both\" name=\"0\"><transport xmlns=\"urn:xmpp:jingle:transports:ice-udp:1\" pwd=\"XKe021opw+vupIkkLCI1+kP4\" ufrag=\"Pt2c\"><candidate xmlns=\"urn:xmpp:jingle:transports:ice-udp:1\" id=\"563352000\" component=\"2\" foundation=\"1076231993\" generation=\"0\" ip=\"198.51.100.52\" port=\"50002\" priority=\"41885694\" protocol=\"udp\" rel-addr=\"0.0.0.0\" rel_port=\"0\" type=\"relay\"/><trickle xmlns=\"http://gultsch.de/xmpp/drafts/jingle/transports/ice-udp/option\"/><renomination xmlns=\"http://gultsch.de/xmpp/drafts/jingle/transports/ice-udp/option\"/><fingerprint xmlns=\"urn:xmpp:jingle:apps:dtls:0\" hash=\"sha-256\" setup=\"actpass\">1F:CE:47:40:5F:F2:FC:66:F2:21:F7:7D:3D:D6:0D:B0:67:6F:BD:CF:8B:0E:B7:90:5D:8C:33:9E:AD:F2:CB:FC</fingerprint></transport><description xmlns=\"urn:xmpp:jingle:apps:rtp:1\" media=\"audio\"><extmap-allow-mixed/><rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"1\" uri=\"urn:ietf:params:rtp-hdrext:ssrc-audio-level\"/><rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"2\" uri=\"http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\"/><rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"3\" uri=\"http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\"/><rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"4\" uri=\"urn:ietf:params:rtp-hdrext:sdes:mid\"/><rtcp-mux/><payload-type id=\"9\" name=\"G722\" clockrate=\"8000\"/><payload-type id=\"111\" name=\"opus\" clockrate=\"48000\" channels=\"2\"><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"transport-cc\"/><parameter name=\"profile_level_id\" value=\"4325392\"/><parameter name=\"useinbandfec\" value=\"true\"/><parameter name=\"minptime\" value=\"10\"/></payload-type><payload-type id=\"102\" name=\"ILBC\" clockrate=\"8000\"/><payload-type id=\"126\" name=\"telephone-event\" clockrate=\"8000\"/><payload-type id=\"0\" name=\"PCMU\" clockrate=\"8000\"/><payload-type id=\"63\" name=\"red\" clockrate=\"48000\" channels=\"2\"><parameter name=\"profile_level_id\" value=\"4325392\"/><parameter name=\"encodings\" value=\"111\"/><parameter name=\"encodings\" value=\"111\"/></payload-type><payload-type id=\"110\" name=\"telephone-event\" clockrate=\"48000\"/><payload-type id=\"8\" name=\"PCMA\" clockrate=\"8000\"/><payload-type id=\"13\" name=\"CN\" clockrate=\"8000\"/><source xmlns=\"urn:xmpp:jingle:apps:rtp:ssma:0\" ssrc=\"109112503\"><parameter name=\"cname\" value=\"vUpPwDICjVuwEwGO\"/><parameter name=\"msid\" value=\"stream audio0\"/></source></description></content><content xmlns=\"urn:xmpp:jingle:1\" creator=\"initiator\" senders=\"both\" name=\"1\"><transport xmlns=\"urn:xmpp:jingle:transports:ice-udp:1\" pwd=\"XKe021opw+vupIkkLCI1+kP4\" ufrag=\"Pt2c\"><trickle xmlns=\"http://gultsch.de/xmpp/drafts/jingle/transports/ice-udp/option\"/><renomination xmlns=\"http://gultsch.de/xmpp/drafts/jingle/transports/ice-udp/option\"/><fingerprint xmlns=\"urn:xmpp:jingle:apps:dtls:0\" hash=\"sha-256\" setup=\"actpass\">1F:CE:47:40:5F:F2:FC:66:F2:21:F7:7D:3D:D6:0D:B0:67:6F:BD:CF:8B:0E:B7:90:5D:8C:33:9E:AD:F2:CB:FC</fingerprint></transport><description xmlns=\"urn:xmpp:jingle:apps:rtp:1\" media=\"video\"><extmap-allow-mixed/><rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"14\" uri=\"urn:ietf:params:rtp-hdrext:toffset\"/><rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"2\" uri=\"http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\"/><rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"13\" uri=\"urn:3gpp:video-orientation\"/><rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"3\" uri=\"http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\"/><rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"5\" uri=\"http://www.webrtc.org/experiments/rtp-hdrext/playout-delay\"/><rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"6\" uri=\"http://www.webrtc.org/experiments/rtp-hdrext/video-content-type\"/><rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"7\" uri=\"http://www.webrtc.org/experiments/rtp-hdrext/video-timing\"/><rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"8\" uri=\"http://www.webrtc.org/experiments/rtp-hdrext/color-space\"/><rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"4\" uri=\"urn:ietf:params:rtp-hdrext:sdes:mid\"/><rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"10\" uri=\"urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id\"/><rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"11\" uri=\"urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id\"/><rtcp-mux/><ssrc-group xmlns=\"urn:xmpp:jingle:apps:rtp:ssma:0\" semantics=\"FID\"><source ssrc=\"3733210709\"/><source ssrc=\"4025710505\"/></ssrc-group><payload-type id=\"103\" name=\"rtx\" clockrate=\"90000\"><parameter name=\"profile_level_id\" value=\"4325392\"/><parameter name=\"apt\" value=\"127\"/></payload-type><payload-type id=\"101\" name=\"rtx\" clockrate=\"90000\"><parameter name=\"profile_level_id\" value=\"4325392\"/><parameter name=\"apt\" value=\"100\"/></payload-type><payload-type id=\"104\" name=\"red\" clockrate=\"90000\"/><payload-type id=\"96\" name=\"H264\" clockrate=\"90000\"><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"goog-remb\"/><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"transport-cc\"/><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"ccm\" subtype=\"fir\"/><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"nack\"/><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"nack\" subtype=\"pli\"/><parameter name=\"packetization_mode\" value=\"1\"/><parameter name=\"level_asymmetry_allowed\" value=\"true\"/><parameter name=\"profile_level_id\" value=\"6556724\"/><parameter name=\"profile_level_id\" value=\"6556724\"/></payload-type><payload-type id=\"105\" name=\"rtx\" clockrate=\"90000\"><parameter name=\"profile_level_id\" value=\"4325392\"/><parameter name=\"apt\" value=\"104\"/></payload-type><payload-type id=\"35\" name=\"AV1\" clockrate=\"90000\"><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"goog-remb\"/><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"transport-cc\"/><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"ccm\" subtype=\"fir\"/><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"nack\"/><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"nack\" subtype=\"pli\"/></payload-type><payload-type id=\"127\" name=\"VP9\" clockrate=\"90000\"><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"goog-remb\"/><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"transport-cc\"/><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"ccm\" subtype=\"fir\"/><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"nack\"/><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"nack\" subtype=\"pli\"/></payload-type><payload-type id=\"98\" name=\"H264\" clockrate=\"90000\"><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"goog-remb\"/><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"transport-cc\"/><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"ccm\" subtype=\"fir\"/><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"nack\"/><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"nack\" subtype=\"pli\"/><parameter name=\"packetization_mode\" value=\"1\"/><parameter name=\"level_asymmetry_allowed\" value=\"true\"/><parameter name=\"profile_level_id\" value=\"4382772\"/><parameter name=\"profile_level_id\" value=\"4382772\"/></payload-type><payload-type id=\"36\" name=\"rtx\" clockrate=\"90000\"><parameter name=\"profile_level_id\" value=\"4325392\"/><parameter name=\"apt\" value=\"35\"/></payload-type><payload-type id=\"106\" name=\"ulpfec\" clockrate=\"90000\"/><payload-type id=\"99\" name=\"rtx\" clockrate=\"90000\"><parameter name=\"profile_level_id\" value=\"4325392\"/><parameter name=\"apt\" value=\"98\"/></payload-type><payload-type id=\"100\" name=\"VP8\" clockrate=\"90000\"><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"goog-remb\"/><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"transport-cc\"/><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"ccm\" subtype=\"fir\"/><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"nack\"/><rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"nack\" subtype=\"pli\"/></payload-type><payload-type id=\"97\" name=\"rtx\" clockrate=\"90000\"><parameter name=\"profile_level_id\" value=\"4325392\"/><parameter name=\"apt\" value=\"96\"/></payload-type><source xmlns=\"urn:xmpp:jingle:apps:rtp:ssma:0\" ssrc=\"3733210709\"><parameter name=\"cname\" value=\"vUpPwDICjVuwEwGO\"/><parameter name=\"msid\" value=\"stream video0\"/></source><source xmlns=\"urn:xmpp:jingle:apps:rtp:ssma:0\" ssrc=\"4025710505\"><parameter name=\"cname\" value=\"vUpPwDICjVuwEwGO\"/><parameter name=\"msid\" value=\"stream video0\"/></source></description></content></root>";

static NSString* _rawXMLInputString = @"<?xml version=\"1.0\"?>\
<root>\
  <group xmlns=\"urn:xmpp:jingle:apps:grouping:0\" semantics=\"BUNDLE\">\
    <content name=\"0\"/>\
    <content name=\"1\"/>\
  </group>\
  <content xmlns=\"urn:xmpp:jingle:1\" creator=\"initiator\" senders=\"both\" name=\"0\">\
    <transport xmlns=\"urn:xmpp:jingle:transports:ice-udp:1\" pwd=\"+g6eHJ3YWHoXNdOM60q0LH85\" ufrag=\"LlJY\">\
      <trickle xmlns=\"http://gultsch.de/xmpp/drafts/jingle/transports/ice-udp/option\"/>\
      <renomination xmlns=\"http://gultsch.de/xmpp/drafts/jingle/transports/ice-udp/option\"/>\
      <fingerprint xmlns=\"urn:xmpp:jingle:apps:dtls:0\" hash=\"sha-256\" setup=\"actpass\">3D:7C:7D:EC:CC:84:39:F2:46:A9:10:03:9E:09:FD:4D:E7:9A:49:6D:54:84:F5:5A:10:C1:09:A3:1F:B1:68:D2</fingerprint>\
    </transport>\
    <description xmlns=\"urn:xmpp:jingle:apps:rtp:1\" media=\"audio\">\
      <extmap-allow-mixed/>\
      <rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"1\" uri=\"urn:ietf:params:rtp-hdrext:ssrc-audio-level\"/>\
      <rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"2\" uri=\"http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\"/>\
      <rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"3\" uri=\"http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\"/>\
      <rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"4\" uri=\"urn:ietf:params:rtp-hdrext:sdes:mid\"/>\
      <rtcp-mux/>\
      <payload-type id=\"13\" name=\"CN\" clockrate=\"8000\"/>\
      <payload-type id=\"111\" name=\"opus\" clockrate=\"48000\" channels=\"2\">\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"transport-cc\"/>\
        <parameter name=\"profile_level_id\" value=\"4325392\"/>\
        <parameter name=\"useinbandfec\" value=\"true\"/>\
        <parameter name=\"minptime\" value=\"10\"/>\
      </payload-type>\
      <payload-type id=\"63\" name=\"red\" clockrate=\"48000\" channels=\"2\">\
        <parameter name=\"profile_level_id\" value=\"4325392\"/>\
        <parameter name=\"encodings\" value=\"111\"/>\
        <parameter name=\"encodings\" value=\"111\"/>\
      </payload-type>\
      <payload-type id=\"9\" name=\"G722\" clockrate=\"8000\"/>\
      <payload-type id=\"110\" name=\"telephone-event\" clockrate=\"48000\"/>\
      <payload-type id=\"0\" name=\"PCMU\" clockrate=\"8000\"/>\
      <payload-type id=\"102\" name=\"ILBC\" clockrate=\"8000\"/>\
      <payload-type id=\"8\" name=\"PCMA\" clockrate=\"8000\"/>\
      <payload-type id=\"126\" name=\"telephone-event\" clockrate=\"8000\"/>\
      <source xmlns=\"urn:xmpp:jingle:apps:rtp:ssma:0\" ssrc=\"388312053\">\
        <parameter name=\"cname\" value=\"EKc2Iz0i3z5nyiVy\"/>\
        <parameter name=\"msid\" value=\"stream audio0\"/>\
      </source>\
    </description>\
  </content>\
  <content xmlns=\"urn:xmpp:jingle:1\" creator=\"initiator\" senders=\"both\" name=\"1\">\
    <transport xmlns=\"urn:xmpp:jingle:transports:ice-udp:1\" pwd=\"+g6eHJ3YWHoXNdOM60q0LH85\" ufrag=\"LlJY\">\
      <trickle xmlns=\"http://gultsch.de/xmpp/drafts/jingle/transports/ice-udp/option\"/>\
      <renomination xmlns=\"http://gultsch.de/xmpp/drafts/jingle/transports/ice-udp/option\"/>\
      <fingerprint xmlns=\"urn:xmpp:jingle:apps:dtls:0\" hash=\"sha-256\" setup=\"actpass\">3D:7C:7D:EC:CC:84:39:F2:46:A9:10:03:9E:09:FD:4D:E7:9A:49:6D:54:84:F5:5A:10:C1:09:A3:1F:B1:68:D2</fingerprint>\
    </transport>\
    <description xmlns=\"urn:xmpp:jingle:apps:rtp:1\" media=\"video\">\
      <extmap-allow-mixed/>\
      <rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"14\" uri=\"urn:ietf:params:rtp-hdrext:toffset\"/>\
      <rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"2\" uri=\"http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\"/>\
      <rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"13\" uri=\"urn:3gpp:video-orientation\"/>\
      <rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"3\" uri=\"http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\"/>\
      <rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"5\" uri=\"http://www.webrtc.org/experiments/rtp-hdrext/playout-delay\"/>\
      <rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"6\" uri=\"http://www.webrtc.org/experiments/rtp-hdrext/video-content-type\"/>\
      <rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"7\" uri=\"http://www.webrtc.org/experiments/rtp-hdrext/video-timing\"/>\
      <rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"8\" uri=\"http://www.webrtc.org/experiments/rtp-hdrext/color-space\"/>\
      <rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"4\" uri=\"urn:ietf:params:rtp-hdrext:sdes:mid\"/>\
      <rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"10\" uri=\"urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id\"/>\
      <rtp-hdrext xmlns=\"urn:xmpp:jingle:apps:rtp:rtp-hdrext:0\" id=\"11\" uri=\"urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id\"/>\
      <rtcp-mux/>\
      <ssrc-group xmlns=\"urn:xmpp:jingle:apps:rtp:ssma:0\" semantics=\"FID\">\
        <source ssrc=\"4017423501\"/>\
        <source ssrc=\"2821445958\"/>\
      </ssrc-group>\
      <payload-type id=\"98\" name=\"H264\" clockrate=\"90000\">\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"goog-remb\"/>\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"transport-cc\"/>\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"ccm\" subtype=\"fir\"/>\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"nack\"/>\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"nack\" subtype=\"pli\"/>\
        <parameter name=\"packetization_mode\" value=\"1\"/>\
        <parameter name=\"level_asymmetry_allowed\" value=\"true\"/>\
        <parameter name=\"profile_level_id\" value=\"4382772\"/>\
        <parameter name=\"profile_level_id\" value=\"4382772\"/>\
      </payload-type>\
      <payload-type id=\"127\" name=\"VP9\" clockrate=\"90000\">\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"goog-remb\"/>\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"transport-cc\"/>\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"ccm\" subtype=\"fir\"/>\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"nack\"/>\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"nack\" subtype=\"pli\"/>\
      </payload-type>\
      <payload-type id=\"106\" name=\"ulpfec\" clockrate=\"90000\"/>\
      <payload-type id=\"35\" name=\"AV1\" clockrate=\"90000\">\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"goog-remb\"/>\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"transport-cc\"/>\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"ccm\" subtype=\"fir\"/>\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"nack\"/>\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"nack\" subtype=\"pli\"/>\
      </payload-type>\
      <payload-type id=\"103\" name=\"rtx\" clockrate=\"90000\">\
        <parameter name=\"profile_level_id\" value=\"4325392\"/>\
        <parameter name=\"apt\" value=\"127\"/>\
      </payload-type>\
      <payload-type id=\"97\" name=\"rtx\" clockrate=\"90000\">\
        <parameter name=\"profile_level_id\" value=\"4325392\"/>\
        <parameter name=\"apt\" value=\"96\"/>\
      </payload-type>\
      <payload-type id=\"99\" name=\"rtx\" clockrate=\"90000\">\
        <parameter name=\"profile_level_id\" value=\"4325392\"/>\
        <parameter name=\"apt\" value=\"98\"/>\
      </payload-type>\
      <payload-type id=\"36\" name=\"rtx\" clockrate=\"90000\">\
        <parameter name=\"profile_level_id\" value=\"4325392\"/>\
        <parameter name=\"apt\" value=\"35\"/>\
      </payload-type>\
      <payload-type id=\"96\" name=\"H264\" clockrate=\"90000\">\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"goog-remb\"/>\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"transport-cc\"/>\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"ccm\" subtype=\"fir\"/>\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"nack\"/>\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"nack\" subtype=\"pli\"/>\
        <parameter name=\"packetization_mode\" value=\"1\"/>\
        <parameter name=\"level_asymmetry_allowed\" value=\"true\"/>\
        <parameter name=\"profile_level_id\" value=\"6556724\"/>\
        <parameter name=\"profile_level_id\" value=\"6556724\"/>\
      </payload-type>\
      <payload-type id=\"104\" name=\"red\" clockrate=\"90000\"/>\
      <payload-type id=\"100\" name=\"VP8\" clockrate=\"90000\">\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"goog-remb\"/>\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"transport-cc\"/>\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"ccm\" subtype=\"fir\"/>\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"nack\"/>\
        <rtcp-fb xmlns=\"urn:xmpp:jingle:apps:rtp:rtcp-fb:0\" type=\"nack\" subtype=\"pli\"/>\
      </payload-type>\
      <payload-type id=\"101\" name=\"rtx\" clockrate=\"90000\">\
        <parameter name=\"profile_level_id\" value=\"4325392\"/>\
        <parameter name=\"apt\" value=\"100\"/>\
      </payload-type>\
      <payload-type id=\"105\" name=\"rtx\" clockrate=\"90000\">\
        <parameter name=\"profile_level_id\" value=\"4325392\"/>\
        <parameter name=\"apt\" value=\"104\"/>\
      </payload-type>\
      <source xmlns=\"urn:xmpp:jingle:apps:rtp:ssma:0\" ssrc=\"4017423501\">\
        <parameter name=\"cname\" value=\"EKc2Iz0i3z5nyiVy\"/>\
        <parameter name=\"msid\" value=\"stream video0\"/>\
      </source>\
      <source xmlns=\"urn:xmpp:jingle:apps:rtp:ssma:0\" ssrc=\"2821445958\">\
        <parameter name=\"cname\" value=\"EKc2Iz0i3z5nyiVy\"/>\
        <parameter name=\"msid\" value=\"stream video0\"/>\
      </source>\
    </description>\
  </content>\
</root>";
    NSString* _rawSDPOutputString = @"v=0\
o=- 2005859539484728435 2 IN IP4 127.0.0.1\
s=-\
t=0 0\
a=group:BUNDLE 0 1\
a=msid-semantic: WMS stream\
m=audio 9 UDP/TLS/RTP/SAVP 13 111 63 9 110 0 102 8 126\
c=IN IP4 0.0.0.0\
a=sendrecv\
a=mid:0\
a=rtcp:9 IN IP4 0.0.0.0\
a=ice-pwd:+g6eHJ3YWHoXNdOM60q0LH85\
a=ice-ufrag:LlJY\
a=fingerprint:sha-256 3D:7C:7D:EC:CC:84:39:F2:46:A9:10:03:9E:09:FD:4D:E7:9A:49:6D:54:84:F5:5A:10:C1:09:A3:1F:B1:68:D2\
a=setup:actpass\
a=extmap-allow-mixed\
a=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level\
a=extmap:2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\
a=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\
a=extmap:4 urn:ietf:params:rtp-hdrext:sdes:mid\
a=rtcp-mux\
a=rtpmap:13 CN/8000\
a=rtpmap:111 opus/48000/2\
a=rtcp-fb:111 transport-cc\
a=fmtp:111 minptime=10;useinbandfec=1\
a=rtpmap:63 red/48000/2\
a=fmtp:63 111/111\
a=rtpmap:9 G722/8000\
a=rtpmap:110 telephone-event/48000\
a=rtpmap:0 PCMU/8000\
a=rtpmap:102 ILBC/8000\
a=rtpmap:8 PCMA/8000\
a=rtpmap:126 telephone-event/8000\
a=ssrc:388312053 cname:EKc2Iz0i3z5nyiVy\
a=ssrc:388312053 msid:stream audio0\
a=ice-options:trickle renomination\
m=video 9 UDP/TLS/RTP/SAVP 98 127 106 35 103 97 99 36 96 104 100 101 105\
c=IN IP4 0.0.0.0\
a=sendrecv\
a=mid:1\
a=rtcp:9 IN IP4 0.0.0.0\
a=ice-pwd:+g6eHJ3YWHoXNdOM60q0LH85\
a=ice-ufrag:LlJY\
a=fingerprint:sha-256 3D:7C:7D:EC:CC:84:39:F2:46:A9:10:03:9E:09:FD:4D:E7:9A:49:6D:54:84:F5:5A:10:C1:09:A3:1F:B1:68:D2\
a=setup:actpass\
a=extmap-allow-mixed\
a=extmap:14 urn:ietf:params:rtp-hdrext:toffset\
a=extmap:2 http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time\
a=extmap:13 urn:3gpp:video-orientation\
a=extmap:3 http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01\
a=extmap:5 http://www.webrtc.org/experiments/rtp-hdrext/playout-delay\
a=extmap:6 http://www.webrtc.org/experiments/rtp-hdrext/video-content-type\
a=extmap:7 http://www.webrtc.org/experiments/rtp-hdrext/video-timing\
a=extmap:8 http://www.webrtc.org/experiments/rtp-hdrext/color-space\
a=extmap:4 urn:ietf:params:rtp-hdrext:sdes:mid\
a=extmap:10 urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id\
a=extmap:11 urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id\
a=rtcp-mux\
a=ssrc-group:FID 4017423501 2821445958\
a=rtpmap:98 H264/90000\
a=rtcp-fb:98 goog-remb\
a=rtcp-fb:98 transport-cc\
a=rtcp-fb:98 ccm fir\
a=rtcp-fb:98 nack\
a=rtcp-fb:98 nack pli\
a=fmtp:98 profile-level-id=42e034;level-asymmetry-allowed=1;packetization-mode=1\
a=rtpmap:127 VP9/90000\
a=rtcp-fb:127 goog-remb\
a=rtcp-fb:127 transport-cc\
a=rtcp-fb:127 ccm fir\
a=rtcp-fb:127 nack\
a=rtcp-fb:127 nack pli\
a=fmtp:127 \
a=rtpmap:106 ulpfec/90000\
a=rtpmap:35 AV1/90000\
a=rtcp-fb:35 goog-remb\
a=rtcp-fb:35 transport-cc\
a=rtcp-fb:35 ccm fir\
a=rtcp-fb:35 nack\
a=rtcp-fb:35 nack pli\
a=fmtp:35 \
a=rtpmap:103 rtx/90000\
a=fmtp:103 apt=127\
a=rtpmap:97 rtx/90000\
a=fmtp:97 apt=96\
a=rtpmap:99 rtx/90000\
a=fmtp:99 apt=98\
a=rtpmap:36 rtx/90000\
a=fmtp:36 apt=35\
a=rtpmap:96 H264/90000\
a=rtcp-fb:96 goog-remb\
a=rtcp-fb:96 transport-cc\
a=rtcp-fb:96 ccm fir\
a=rtcp-fb:96 nack\
a=rtcp-fb:96 nack pli\
a=fmtp:96 profile-level-id=640c34;level-asymmetry-allowed=1;packetization-mode=1\
a=rtpmap:104 red/90000\
a=rtpmap:100 VP8/90000\
a=rtcp-fb:100 goog-remb\
a=rtcp-fb:100 transport-cc\
a=rtcp-fb:100 ccm fir\
a=rtcp-fb:100 nack\
a=rtcp-fb:100 nack pli\
a=fmtp:100 \
a=rtpmap:101 rtx/90000\
a=fmtp:101 apt=100\
a=rtpmap:105 rtx/90000\
a=fmtp:105 apt=104\
a=ssrc:4017423501 cname:EKc2Iz0i3z5nyiVy\
a=ssrc:4017423501 msid:stream video0\
a=ssrc:2821445958 cname:EKc2Iz0i3z5nyiVy\
a=ssrc:2821445958 msid:stream video0\
a=ice-options:trickle renomination\
";

@interface SDPTest : XCTestCase
@end

@implementation SDPTest

-(void) setUp
{
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

-(void) tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
}

/*
-(void) testRawSDP2XMLString
{
    NSString* xmlString = [JingleSDPBridge getJingleStringForSDPString:_rawSDPString withInitiator:YES];
    XCTAssertEqualObjects(xmlString, _rawXMLString, "rust parsed sdp should match xml string");
}

-(void) testRawXMLString2SDP
{
    NSString* sdpString = [JingleSDPBridge getSDPStringForJingleString:_rawXMLInputString withInitiator:YES];
    XCTAssertEqualObjects(sdpString, _rawSDPOutputString, "rust parsed sdp should match xml string");
}

-(void) testSDP2XMLNodes
{
    NSArray<MLXMLNode*>* xmlNodes = [HelperTools sdp2xml:_rawSDPString withInitiator:YES];
    NSArray<NSString*>* xmlStrings = @[
        @"<group xmlns='urn:xmpp:jingle:apps:grouping:0' semantics='BUNDLE'><content name='0'/><content name='1'/><content name='2'/></group>",
        @"<content senders='both' xmlns='urn:xmpp:jingle:1' creator='initiator' name='0'><transport pwd='XKe021opw+vupIkkLCI1+kP4' ufrag='Pt2c' xmlns='urn:xmpp:jingle:transports:ice-udp:1'><candidate id='563352000' rel_port='0' protocol='udp' generation='0' component='2' foundation='1076231993' priority='41885694' type='relay' ip='198.51.100.52' rel-addr='0.0.0.0' port='50002'/><trickle xmlns='http://gultsch.de/xmpp/drafts/jingle/transports/ice-udp/option'/><renomination xmlns='http://gultsch.de/xmpp/drafts/jingle/transports/ice-udp/option'/><fingerprint hash='sha-256' setup='actpass' xmlns='urn:xmpp:jingle:apps:dtls:0'>1F:CE:47:40:5F:F2:FC:66:F2:21:F7:7D:3D:D6:0D:B0:67:6F:BD:CF:8B:0E:B7:90:5D:8C:33:9E:AD:F2:CB:FC</fingerprint></transport><description media='audio' xmlns='urn:xmpp:jingle:apps:rtp:1'><extmap-allow-mixed/><rtp-hdrext id='1' uri='urn:ietf:params:rtp-hdrext:ssrc-audio-level' xmlns='urn:xmpp:jingle:apps:rtp:rtp-hdrext:0'/><rtp-hdrext id='2' uri='http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time' xmlns='urn:xmpp:jingle:apps:rtp:rtp-hdrext:0'/><rtp-hdrext id='3' uri='http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01' xmlns='urn:xmpp:jingle:apps:rtp:rtp-hdrext:0'/><rtp-hdrext id='4' uri='urn:ietf:params:rtp-hdrext:sdes:mid' xmlns='urn:xmpp:jingle:apps:rtp:rtp-hdrext:0'/><rtcp-mux/><payload-type id='9' clockrate='8000' name='G722'/><payload-type id='111' clockrate='48000' channels='2' name='opus'><rtcp-fb type='transport-cc' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><parameter name='profile_level_id' value='4325392'/><parameter name='useinbandfec' value='true'/><parameter name='minptime' value='10'/></payload-type><payload-type id='102' clockrate='8000' name='ILBC'/><payload-type id='126' clockrate='8000' name='telephone-event'/><payload-type id='0' clockrate='8000' name='PCMU'/><payload-type id='63' clockrate='48000' channels='2' name='red'><parameter name='profile_level_id' value='4325392'/><parameter name='encodings' value='111'/><parameter name='encodings' value='111'/></payload-type><payload-type id='110' clockrate='48000' name='telephone-event'/><payload-type id='8' clockrate='8000' name='PCMA'/><payload-type id='13' clockrate='8000' name='CN'/><source ssrc='109112503' xmlns='urn:xmpp:jingle:apps:rtp:ssma:0'><parameter name='cname' value='vUpPwDICjVuwEwGO'/><parameter name='msid' value='stream audio0'/></source></description></content>",
        @"<content senders='both' xmlns='urn:xmpp:jingle:1' creator='initiator' name='1'><transport pwd='XKe021opw+vupIkkLCI1+kP4' ufrag='Pt2c' xmlns='urn:xmpp:jingle:transports:ice-udp:1'><trickle xmlns='http://gultsch.de/xmpp/drafts/jingle/transports/ice-udp/option'/><renomination xmlns='http://gultsch.de/xmpp/drafts/jingle/transports/ice-udp/option'/><fingerprint hash='sha-256' setup='actpass' xmlns='urn:xmpp:jingle:apps:dtls:0'>1F:CE:47:40:5F:F2:FC:66:F2:21:F7:7D:3D:D6:0D:B0:67:6F:BD:CF:8B:0E:B7:90:5D:8C:33:9E:AD:F2:CB:FC</fingerprint></transport><description media='video' xmlns='urn:xmpp:jingle:apps:rtp:1'><extmap-allow-mixed/><rtp-hdrext id='14' uri='urn:ietf:params:rtp-hdrext:toffset' xmlns='urn:xmpp:jingle:apps:rtp:rtp-hdrext:0'/><rtp-hdrext id='2' uri='http://www.webrtc.org/experiments/rtp-hdrext/abs-send-time' xmlns='urn:xmpp:jingle:apps:rtp:rtp-hdrext:0'/><rtp-hdrext id='13' uri='urn:3gpp:video-orientation' xmlns='urn:xmpp:jingle:apps:rtp:rtp-hdrext:0'/><rtp-hdrext id='3' uri='http://www.ietf.org/id/draft-holmer-rmcat-transport-wide-cc-extensions-01' xmlns='urn:xmpp:jingle:apps:rtp:rtp-hdrext:0'/><rtp-hdrext id='5' uri='http://www.webrtc.org/experiments/rtp-hdrext/playout-delay' xmlns='urn:xmpp:jingle:apps:rtp:rtp-hdrext:0'/><rtp-hdrext id='6' uri='http://www.webrtc.org/experiments/rtp-hdrext/video-content-type' xmlns='urn:xmpp:jingle:apps:rtp:rtp-hdrext:0'/><rtp-hdrext id='7' uri='http://www.webrtc.org/experiments/rtp-hdrext/video-timing' xmlns='urn:xmpp:jingle:apps:rtp:rtp-hdrext:0'/><rtp-hdrext id='8' uri='http://www.webrtc.org/experiments/rtp-hdrext/color-space' xmlns='urn:xmpp:jingle:apps:rtp:rtp-hdrext:0'/><rtp-hdrext id='4' uri='urn:ietf:params:rtp-hdrext:sdes:mid' xmlns='urn:xmpp:jingle:apps:rtp:rtp-hdrext:0'/><rtp-hdrext id='10' uri='urn:ietf:params:rtp-hdrext:sdes:rtp-stream-id' xmlns='urn:xmpp:jingle:apps:rtp:rtp-hdrext:0'/><rtp-hdrext id='11' uri='urn:ietf:params:rtp-hdrext:sdes:repaired-rtp-stream-id' xmlns='urn:xmpp:jingle:apps:rtp:rtp-hdrext:0'/><rtcp-mux/><ssrc-group xmlns='urn:xmpp:jingle:apps:rtp:ssma:0' semantics='FID'><source ssrc='3733210709'/><source ssrc='4025710505'/></ssrc-group><payload-type id='103' clockrate='90000' name='rtx'><parameter name='profile_level_id' value='4325392'/><parameter name='apt' value='127'/></payload-type><payload-type id='101' clockrate='90000' name='rtx'><parameter name='profile_level_id' value='4325392'/><parameter name='apt' value='100'/></payload-type><payload-type id='104' clockrate='90000' name='red'/><payload-type id='96' clockrate='90000' name='H264'><rtcp-fb type='goog-remb' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><rtcp-fb type='transport-cc' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><rtcp-fb type='ccm' subtype='fir' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><rtcp-fb type='nack' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><rtcp-fb type='nack' subtype='pli' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><parameter name='packetization_mode' value='1'/><parameter name='level_asymmetry_allowed' value='true'/><parameter name='profile_level_id' value='6556724'/><parameter name='profile_level_id' value='6556724'/></payload-type><payload-type id='105' clockrate='90000' name='rtx'><parameter name='profile_level_id' value='4325392'/><parameter name='apt' value='104'/></payload-type><payload-type id='35' clockrate='90000' name='AV1'><rtcp-fb type='goog-remb' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><rtcp-fb type='transport-cc' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><rtcp-fb type='ccm' subtype='fir' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><rtcp-fb type='nack' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><rtcp-fb type='nack' subtype='pli' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/></payload-type><payload-type id='127' clockrate='90000' name='VP9'><rtcp-fb type='goog-remb' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><rtcp-fb type='transport-cc' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><rtcp-fb type='ccm' subtype='fir' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><rtcp-fb type='nack' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><rtcp-fb type='nack' subtype='pli' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/></payload-type><payload-type id='98' clockrate='90000' name='H264'><rtcp-fb type='goog-remb' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><rtcp-fb type='transport-cc' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><rtcp-fb type='ccm' subtype='fir' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><rtcp-fb type='nack' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><rtcp-fb type='nack' subtype='pli' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><parameter name='packetization_mode' value='1'/><parameter name='level_asymmetry_allowed' value='true'/><parameter name='profile_level_id' value='4382772'/><parameter name='profile_level_id' value='4382772'/></payload-type><payload-type id='36' clockrate='90000' name='rtx'><parameter name='profile_level_id' value='4325392'/><parameter name='apt' value='35'/></payload-type><payload-type id='106' clockrate='90000' name='ulpfec'/><payload-type id='99' clockrate='90000' name='rtx'><parameter name='profile_level_id' value='4325392'/><parameter name='apt' value='98'/></payload-type><payload-type id='100' clockrate='90000' name='VP8'><rtcp-fb type='goog-remb' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><rtcp-fb type='transport-cc' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><rtcp-fb type='ccm' subtype='fir' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><rtcp-fb type='nack' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/><rtcp-fb type='nack' subtype='pli' xmlns='urn:xmpp:jingle:apps:rtp:rtcp-fb:0'/></payload-type><payload-type id='97' clockrate='90000' name='rtx'><parameter name='profile_level_id' value='4325392'/><parameter name='apt' value='96'/></payload-type><source ssrc='3733210709' xmlns='urn:xmpp:jingle:apps:rtp:ssma:0'><parameter name='cname' value='vUpPwDICjVuwEwGO'/><parameter name='msid' value='stream video0'/></source><source ssrc='4025710505' xmlns='urn:xmpp:jingle:apps:rtp:ssma:0'><parameter name='cname' value='vUpPwDICjVuwEwGO'/><parameter name='msid' value='stream video0'/></source></description></content>",
    ];
    int i = 0;
    for(MLXMLNode* node in xmlNodes)
        XCTAssertEqualObjects(node.XMLString, xmlStrings[i++], "sdp should be parsed into proper xml strings");
}

// -(void) testXMLNodes2SDP
// {
//     NSString* sdpString = [HelperTools xml2sdp:xmlNodes withInitiator:YES];
//     XCTAssertEqualObjects(sdpString, _rawSDPString, "xml2sdp should produce a proper sdp string");
// }

*/

@end