use std::{
    any,
    collections::{HashMap, HashSet},
    net::{IpAddr, Ipv4Addr},
};

use serde_derive::{Deserialize, Serialize};
use webrtc_sdp::{
    address::ExplicitlyTypedAddress,
    attribute_type::{
        RtxFmtpParameters, SdpAttribute, SdpAttributeFmtp, SdpAttributeFmtpParameters,
        SdpAttributeMsidSemantic, SdpAttributePayloadType, SdpAttributeRtcp,
        SdpAttributeRtcpFbType, SdpAttributeRtpmap, SdpAttributeSsrc,
    },
    error::SdpParserInternalError,
    media_type::{SdpFormatList, SdpMedia, SdpMediaLine, SdpMediaValue, SdpProtocolValue},
    SdpBandwidth, SdpConnection, SdpOrigin, SdpSession, SdpTiming,
};

use crate::{
    is_none_or_default,
    jingle::{GenericParameter, JingleRtpSessionsValue, Root, RootEnum},
    xep_0176::{JingleTransport, JingleTransportCandidate, JingleTransportItems},
    xep_0293::{RtcpFb, RtcpFbTrrInt},
    xep_0294::JingleHdrext,
    xep_0320::JingleTranportFingerprint,
    xep_0338::ContentGroup,
    xep_0339::{JingleSsrc, JingleSsrcGroup},
};

#[derive(Serialize, Deserialize, Default)]
pub struct Content {
    #[serde(rename = "@xmlns", default)]
    xmlns: String,
    #[serde(rename = "@creator")]
    pub creator: String,
    #[serde(rename = "@senders", default)]
    pub senders: ContentCreator,
    #[serde(rename = "@name")]
    pub name: String,
    #[serde(rename = "$value", skip_serializing_if = "Vec::is_empty", default)]
    pub childs: Vec<JingleDes>,
}

impl Content {
    pub fn new() -> Self {
        Self {
            xmlns: "urn:xmpp:jingle:1".to_string(),
            creator: "initiator".to_string(), // hardcoded, see https://xmpp.org/extensions/xep-0166.html#table-2
            senders: ContentCreator::default(),
            name: String::default(),
            childs: Vec::<JingleDes>::default(),
        }
    }

    pub fn add_transport(&mut self, transport: JingleTransport) {
        self.childs.push(JingleDes::Transport(transport));
    }
}

// *** xep-0167
#[derive(Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum ContentCreator {
    Initiator,
    Responder,
    #[default]
    Both,
}

// *** xep-0167
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum JingleDes {
    Description(JingleRtpSessions),
    Transport(JingleTransport),
    #[serde(other)]
    Invalid,
}

// *** xep-0167
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum JingleRtpSessionMedia {
    Audio,
    Application,
    Video,
}

impl JingleRtpSessionMedia {
    pub fn new_from_sdp(sdp_media_value: &SdpMediaValue) -> Self {
        match sdp_media_value {
            SdpMediaValue::Audio => JingleRtpSessionMedia::Audio,
            SdpMediaValue::Application => JingleRtpSessionMedia::Application,
            SdpMediaValue::Video => JingleRtpSessionMedia::Video,
        }
    }

    pub fn to_sdp(&self) -> SdpMediaValue {
        match self {
            JingleRtpSessionMedia::Audio => SdpMediaValue::Audio,
            JingleRtpSessionMedia::Application => SdpMediaValue::Application,
            JingleRtpSessionMedia::Video => SdpMediaValue::Video,
        }
    }
}

// *** xep-0167
#[derive(Serialize, Deserialize, Default, Clone)]
pub struct JingleRtpSessionsPayloadType {
    #[serde(rename = "@id")]
    id: u8,
    #[serde(rename = "@name", skip_serializing_if = "is_none_or_default")]
    name: Option<String>,
    #[serde(
        rename = "@clockrate",
        skip_serializing_if = "is_none_or_default",
        default
    )]
    clockrate: Option<u32>,
    #[serde(rename = "@channels", skip_serializing_if = "is_none_or_default")]
    channels: Option<u32>,
    #[serde(rename = "@maxptime", skip_serializing_if = "is_none_or_default")]
    maxptime: Option<u32>,
    #[serde(rename = "@ptime", skip_serializing_if = "is_none_or_default")]
    ptime: Option<u32>,
    #[serde(rename = "$value", skip_serializing_if = "Vec::is_empty", default)]
    parameter: Vec<JingleRtpSessionsPayloadTypeValue>,
}

macro_rules! add_nondefault_parameter {
    ( $self: expr, $params: expr, $name: ident ) => {
        if $params.$name != Default::default() {
            $self.add_parameter(stringify!($name), $params.$name.to_string())
        }
    };
}

impl JingleRtpSessionsPayloadType {
    pub fn new(id: u8) -> Self {
        let mut payload_type = Self::default();
        payload_type.set_id(id);
        payload_type
    }

    pub fn id(&self) -> u8 {
        self.id
    }

    pub fn name(&self) -> Option<&str> {
        self.name.as_deref()
    }

    pub fn parameter(&self) -> &Vec<JingleRtpSessionsPayloadTypeValue> {
        &self.parameter
    }

    fn set_id(&mut self, id: u8) {
        self.id = id;
    }

    pub fn fill_from_sdp_rtpmap(&mut self, rtpmap: &SdpAttributeRtpmap) {
        self.id = rtpmap.payload_type;
        self.name = Some(rtpmap.codec_name.clone());
        self.clockrate = Some(rtpmap.frequency);
        self.channels = rtpmap.channels;
    }

    pub fn fill_from_sdp_fmtp(&mut self, params: &SdpAttributeFmtpParameters) {
        self.maxptime = Some(params.maxptime);
        self.ptime = Some(params.ptime);

        add_nondefault_parameter!(self, params, packetization_mode);
        add_nondefault_parameter!(self, params, level_asymmetry_allowed);

        add_nondefault_parameter!(self, params, profile_level_id);
        // this has a default of 0x420010 which is different to the datatype-default of 0
        // see: https://stackoverflow.com/questions/20634476/is-sprop-parameter-sets-or-profile-level-id-the-sdp-parameter-required-to-decode
        if params.profile_level_id != 0x420010 && params.profile_level_id != 0 {
            self.add_parameter("profile_level_id", params.profile_level_id.to_string());
        }
        add_nondefault_parameter!(self, params, max_fs);
        add_nondefault_parameter!(self, params, max_cpb);
        add_nondefault_parameter!(self, params, max_dpb);
        add_nondefault_parameter!(self, params, max_br);
        add_nondefault_parameter!(self, params, max_mbps);

        // VP8 and VP9
        // max_fs, already defined in H264
        add_nondefault_parameter!(self, params, max_fr);

        // Opus https://tools.ietf.org/html/rfc7587
        // this has a default of 48000 which is different to the datatype-default of 0
        if params.maxplaybackrate != 48000 && params.maxplaybackrate != 0 {
            self.add_parameter("maxplaybackrate", params.maxplaybackrate.to_string());
        }
        add_nondefault_parameter!(self, params, maxaveragebitrate);
        add_nondefault_parameter!(self, params, usedtx);
        add_nondefault_parameter!(self, params, stereo);
        add_nondefault_parameter!(self, params, useinbandfec);
        add_nondefault_parameter!(self, params, cbr);
        // ptime already set in payload type
        add_nondefault_parameter!(self, params, minptime);
        // maxptime already set in payload type

        for i in &params.encodings {
            self.add_parameter("encodings", i.to_string());
        }
        if params.dtmf_tones != String::default() {
            self.add_parameter("dtmp_tones", params.dtmf_tones.to_string());
        }

        // rtx
        match params.rtx {
            None => {}
            Some(rtx) => {
                self.add_parameter("apt", rtx.apt.to_string());
                match rtx.rtx_time {
                    None => {}
                    Some(time) => {
                        self.add_parameter("rtx-time", time.to_string());
                    }
                };
            }
        };

        for token in &params.unknown_tokens {
            for param in GenericParameter::parse_parameter_string(token) {
                if let Some(value) = param.value() {
                    self.parameter
                        .push(JingleRtpSessionsPayloadTypeValue::Parameter(
                            JingleRtpSessionsPayloadTypeParam::new(
                                param.name().to_string(),
                                value.to_string(),
                            ),
                        ));
                }
            }
        }
    }

    pub fn add_parameter(&mut self, name: &str, value: String) {
        self.parameter
            .push(JingleRtpSessionsPayloadTypeValue::Parameter(
                JingleRtpSessionsPayloadTypeParam::new(name.to_string(), value),
            ));
    }

    pub fn add_rtcp_fb(&mut self, rtcp_fb: RtcpFb) {
        self.parameter
            .push(JingleRtpSessionsPayloadTypeValue::RtcpFb(rtcp_fb));
    }

    pub fn add_rtcp_fb_trr_int(&mut self, rtcp_fb_trr_int: RtcpFbTrrInt) {
        self.parameter
            .push(JingleRtpSessionsPayloadTypeValue::RtcpFbTrrInt(
                rtcp_fb_trr_int,
            ));
    }

    fn get_fmtp_param<T>(&self, known_param_names: &mut HashSet<String>, name: &str) -> T
    where
        T: Default + std::str::FromStr + Clone,
    {
        match self
            .get_fmtp_param_vec::<T>(known_param_names, name)
            .first()
        {
            Some(value) => value.clone(),
            _ => T::default(),
        }
    }

    fn get_fmtp_param_vec<T>(&self, known_param_names: &mut HashSet<String>, name: &str) -> Vec<T>
    where
        T: std::str::FromStr + Clone,
    {
        let mut retval: Vec<T> = Vec::new();
        for param in &self.parameter {
            match param {
                JingleRtpSessionsPayloadTypeValue::Parameter(param) if param.name == name => {
                    known_param_names.insert(name.to_string());
                    let mut value = param.value.clone();
                    //bool preprocessing (in xmpp "1" and "true" are defined as true, while "0" and "false are defined as false)
                    //TODO: implement this for quickxml deserialization, too!
                    if any::type_name::<T>() == any::type_name::<bool>() {
                        match param.value.to_lowercase().as_str() {
                            "false" => value = "false".to_string().clone(),
                            "0" => value = "false".to_string().clone(),
                            "true" => value = "true".to_string().clone(),
                            "1" => value = "true".to_string().clone(),
                            _ => {
                                panic!("unallowed truth value: {}", value)
                            }
                        };
                    }
                    match value.parse::<T>() {
                        Err(_) => {
                            eprintln!(
                                "Error extracting fmtp parameter '{}': wrong type of value '{}'!",
                                name, param.value
                            )
                        }
                        Ok(value) => retval.push(value.clone()),
                    };
                }
                _ => {}
            }
        }
        retval
    }

    fn get_fmtp_unknown_tokens_vec(&self, known_param_names: &HashSet<String>) -> Vec<String> {
        let mut retval: Vec<String> = Vec::new();
        for param in &self.parameter {
            match param {
                JingleRtpSessionsPayloadTypeValue::Parameter(param)
                    if !known_param_names.contains(&param.name) =>
                {
                    retval.push(format!("{}={}", param.name, param.value));
                }
                _ => {}
            }
        }
        retval
    }

    pub fn to_sdp_fmtp(&self) -> Result<Option<SdpAttributeFmtp>, SdpParserInternalError> {
        // don't return any SdpAttributeFmtp if no attributes are present in xml
        // this avoids returning default values for everything, which results in bogus sdp
        if self.parameter.is_empty() {
            return Ok(None);
        }
        let mut known_param_names: HashSet<String> = HashSet::new();
        let mut retval = SdpAttributeFmtp {
            payload_type: self.id,
            parameters: SdpAttributeFmtpParameters {
                packetization_mode: self
                    .get_fmtp_param(&mut known_param_names, "packetization_mode"),
                level_asymmetry_allowed: self
                    .get_fmtp_param(&mut known_param_names, "level_asymmetry_allowed"),
                // this has a default of 0x420010 which is different to the datatype-default of 0
                // see: https://stackoverflow.com/questions/20634476/is-sprop-parameter-sets-or-profile-level-id-the-sdp-parameter-required-to-decode
                profile_level_id: match self
                    .get_fmtp_param_vec::<u32>(&mut known_param_names, "profile_level_id")
                    .is_empty()
                {
                    true => 0x420010,
                    false => self.get_fmtp_param(&mut known_param_names, "profile_level_id"),
                },
                max_fs: self.get_fmtp_param(&mut known_param_names, "max_fs"),
                max_cpb: self.get_fmtp_param(&mut known_param_names, "max_cpb"),
                max_dpb: self.get_fmtp_param(&mut known_param_names, "max_dpb"),
                max_br: self.get_fmtp_param(&mut known_param_names, "max_br"),
                max_mbps: self.get_fmtp_param(&mut known_param_names, "max_mbps"),
                max_fr: self.get_fmtp_param(&mut known_param_names, "max_fr"),
                // this has a default of 48000 which is different to the datatype-default of 0
                maxplaybackrate: match self
                    .get_fmtp_param_vec::<u32>(&mut known_param_names, "maxplaybackrate")
                    .is_empty()
                {
                    true => 48000,
                    false => self.get_fmtp_param(&mut known_param_names, "maxplaybackrate"),
                },
                maxaveragebitrate: self.get_fmtp_param(&mut known_param_names, "maxaveragebitrate"),
                usedtx: self.get_fmtp_param(&mut known_param_names, "usedtx"),
                stereo: self.get_fmtp_param(&mut known_param_names, "stereo"),
                useinbandfec: self.get_fmtp_param(&mut known_param_names, "useinbandfec"),
                cbr: self.get_fmtp_param(&mut known_param_names, "cbr"),
                ptime: self.ptime.unwrap_or_default(),
                minptime: self.get_fmtp_param(&mut known_param_names, "minptime"),
                maxptime: self.maxptime.unwrap_or_default(),
                encodings: self.get_fmtp_param_vec(&mut known_param_names, "encodings"),
                dtmf_tones: self.get_fmtp_param(&mut known_param_names, "dtmf_tones"),
                // use get_fmtp_param_vec() to search for existence because get_fmtp_param() does not return an Option() but a default value for T
                rtx: match self
                    .get_fmtp_param_vec::<u8>(&mut known_param_names, "apt")
                    .is_empty()
                {
                    true => None,
                    false => Some(RtxFmtpParameters {
                        apt: self.get_fmtp_param::<u8>(&mut known_param_names, "apt"),
                        rtx_time: match self
                            .get_fmtp_param_vec::<u32>(&mut known_param_names, "rtx-time")
                            .is_empty()
                        {
                            true => None,
                            false => {
                                Some(self.get_fmtp_param::<u32>(&mut known_param_names, "rtx-time"))
                            }
                        },
                    }),
                },
                unknown_tokens: Vec::new(),
            },
        };
        retval.parameters.unknown_tokens = self.get_fmtp_unknown_tokens_vec(&known_param_names);
        Ok(Some(retval))
    }

    pub fn to_sdp_rtpmap(&self) -> SdpAttributeRtpmap {
        SdpAttributeRtpmap {
            payload_type: self.id,
            codec_name: match &self.name {
                Some(name) => name.to_string(),
                None => "".to_string(),
            },
            frequency: self.clockrate.unwrap_or_default(),
            channels: self.channels,
        }
    }
}

// *** xep-0167
#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "kebab-case")]
pub enum JingleRtpSessionsPayloadTypeValue {
    Parameter(JingleRtpSessionsPayloadTypeParam),
    RtcpFbTrrInt(RtcpFbTrrInt),
    RtcpFb(RtcpFb),
    #[serde(other)]
    Invalid,
}

// *** xep-0167
#[derive(Serialize, Deserialize, Clone)]
pub struct JingleRtpSessionsPayloadTypeParam {
    #[serde(rename = "@name")]
    name: String,
    #[serde(rename = "@value")]
    value: String,
}

impl JingleRtpSessionsPayloadTypeParam {
    pub fn new(name: String, value: String) -> Self {
        Self { name, value }
    }
}

// *** xep-0167
#[derive(Serialize, Deserialize, Clone)]
pub struct JingleRtpSessionsBandwidth {
    #[serde(rename = "type")]
    bwtype: String,
    value: u32, // TODO: should be u128
}

impl JingleRtpSessionsBandwidth {
    pub fn new_from_sdp(sdp_bandwidth: &SdpBandwidth) -> Self {
        let (bwtype, value) = match sdp_bandwidth {
            SdpBandwidth::As(value) => ("AS".to_string(), value),
            SdpBandwidth::Ct(value) => ("CT".to_string(), value),
            SdpBandwidth::Tias(value) => ("TIAS".to_string(), value),
            SdpBandwidth::Unknown(bwtype, value) => (bwtype.to_string(), value),
        };
        Self {
            bwtype,
            value: *value,
        }
    }

    pub fn to_sdp(&self) -> SdpBandwidth {
        match self.bwtype.to_ascii_uppercase().as_str() {
            "AS" => SdpBandwidth::As(self.value),
            "CT" => SdpBandwidth::Ct(self.value),
            "TIAS" => SdpBandwidth::Tias(self.value),
            _ => SdpBandwidth::Unknown(self.bwtype.to_string(), self.value),
        }
    }
}

// *** xep-0167
#[derive(Serialize, Deserialize)]
pub struct JingleRtpSessions {
    #[serde(rename = "@xmlns", default)]
    xmlns: String,
    #[serde(rename = "@media")]
    media: JingleRtpSessionMedia,
    #[serde(rename = "$value", skip_serializing_if = "Vec::is_empty", default)]
    item: Vec<JingleRtpSessionsValue>,
    #[serde(skip)]
    payload_helper: HashMap<u8, JingleRtpSessionsPayloadType>,
    #[serde(skip)]
    ssrc_helper: HashMap<u32, JingleSsrc>,
}

impl JingleRtpSessions {
    fn new(sdp_media: &SdpMediaValue) -> Self {
        Self {
            xmlns: "urn:xmpp:jingle:apps:rtp:1".to_string(),
            media: JingleRtpSessionMedia::new_from_sdp(sdp_media),
            item: Vec::new(),
            payload_helper: HashMap::new(),
            ssrc_helper: HashMap::new(),
        }
    }

    pub fn item(&self) -> &Vec<JingleRtpSessionsValue> {
        &self.item
    }

    pub fn media(&self) -> &JingleRtpSessionMedia {
        &self.media
    }

    pub fn fill_from_payload_helper(&mut self) {
        for (_, payload) in self.payload_helper.iter() {
            self.item
                .push(JingleRtpSessionsValue::PayloadType(payload.clone()));
        }
    }

    fn get_payload_type(&mut self, id: u8) -> &mut JingleRtpSessionsPayloadType {
        let p_t = self
            .payload_helper
            .entry(id)
            .or_insert(JingleRtpSessionsPayloadType::new(id));
        p_t
    }

    pub fn fill_from_ssrc_helper(&mut self) {
        for (_, ssrc) in self.ssrc_helper.iter() {
            self.item.push(JingleRtpSessionsValue::Source(ssrc.clone()));
        }
    }

    fn get_ssrc(&mut self, id: u32) -> &mut JingleSsrc {
        let ssrc = self.ssrc_helper.entry(id).or_insert(JingleSsrc::new(id));
        ssrc
    }

    pub fn add_ssrc(&mut self, ssrc: &SdpAttributeSsrc) {
        let jingle_ssrc = self.get_ssrc(ssrc.id);
        if let Some(attribute) = &ssrc.attribute {
            match &ssrc.value {
                Some(value) => jingle_ssrc.add_parameter(attribute, Some(value.to_string())),
                _ => jingle_ssrc.add_parameter(attribute, None),
            }
        }
    }

    pub fn add_ssrc_group(&mut self, ssrc_group: JingleSsrcGroup) {
        self.item
            .push(JingleRtpSessionsValue::SsrcGroup(ssrc_group));
    }

    pub fn add_extmap_allow_mixed(&mut self) {
        self.item.push(JingleRtpSessionsValue::ExtmapAllowMixed);
    }

    pub fn add_extmap_hdrext(&mut self, hdrext: JingleHdrext) {
        self.item.push(JingleRtpSessionsValue::RtpHdrext(hdrext));
    }

    pub fn add_sdp_bandwith(&mut self, jingle_bandwith: JingleRtpSessionsBandwidth) {
        self.item
            .push(JingleRtpSessionsValue::Bandwidth(jingle_bandwith));
    }

    pub fn add_rtcp_mux(&mut self) {
        self.item.push(JingleRtpSessionsValue::RtcpMux);
    }

    pub fn add_rtcp_fb(&mut self, rtcp_fb: RtcpFb) {
        self.item.push(JingleRtpSessionsValue::RtcpFb(rtcp_fb));
    }

    pub fn add_rtcp_fb_trr_int(&mut self, rtcp_fb_trr_int: RtcpFbTrrInt) {
        self.item
            .push(JingleRtpSessionsValue::RtcpFbTrrInt(rtcp_fb_trr_int));
    }

    pub fn from_sdp(sdp: &SdpSession, initiator: bool) -> Result<Root, SdpParserInternalError> {
        let mut root = Root::default();

        let mut has_global_extmap_allow_mixed: bool = false; //translate global ExtmapAllowMixed to media-local ExtmapAllowMixed values
        for attribute in &sdp.attribute {
            match attribute {
                SdpAttribute::Group(group) => {
                    root.push(RootEnum::Group(ContentGroup::new_from_sdp(group)));
                }
                SdpAttribute::ExtmapAllowMixed => {
                    has_global_extmap_allow_mixed = true;
                }
                _ => {} //ignore all other global attributes
            }
        }

        for media in &sdp.media {
            let mut content: Content = Content::new();
            let mut jingle: JingleRtpSessions = Self::new(media.get_type());
            if has_global_extmap_allow_mixed {
                jingle.add_extmap_allow_mixed();
            }

            let mut attribute_map: HashMap<u8, Vec<SdpAttribute>> = HashMap::new();
            let format_ids = match media.get_formats() {
                SdpFormatList::Strings(_) => {
                    // Ignore data-channel
                    continue;
                }
                SdpFormatList::Integers(formats) => formats,
            };
            for format in format_ids {
                attribute_map.insert(*format as u8, Vec::new());
            }

            let mut media_transport = JingleTransport::new();
            let mut fingerprint = JingleTranportFingerprint::new();
            for attribute in media.get_attributes() {
                match attribute {
                    SdpAttribute::BundleOnly => {}
                    SdpAttribute::Candidate(candidate) => {
                        media_transport
                            .add_candidate(JingleTransportCandidate::new_from_sdp(candidate)?);
                        //use ufrag from candidate if not (yet) set by dedicated ufrag attribute
                        //(may be be overwritten if we encounter a dedicated ufrag attribute later on)
                        if media_transport.get_ufrag().is_none() {
                            if let Some(ufrag) = &candidate.ufrag {
                                media_transport.set_ufrag(ufrag.clone());
                            }
                        }
                    }
                    SdpAttribute::DtlsMessage(_) => {}
                    SdpAttribute::EndOfCandidates => {}
                    SdpAttribute::Extmap(hdrext) => {
                        jingle.add_extmap_hdrext(JingleHdrext::new_from_sdp(initiator, hdrext));
                    }
                    SdpAttribute::ExtmapAllowMixed => {
                        if !has_global_extmap_allow_mixed {
                            jingle.add_extmap_allow_mixed();
                        }
                    }
                    SdpAttribute::Fingerprint(f) => {
                        fingerprint.set_fingerprint(f);
                    }
                    SdpAttribute::Fmtp(fmtp) => {
                        jingle
                            .get_payload_type(fmtp.payload_type)
                            .fill_from_sdp_fmtp(&fmtp.parameters);
                    }
                    SdpAttribute::Group(_) => {}
                    SdpAttribute::IceLite => {}
                    SdpAttribute::IceMismatch => {}
                    SdpAttribute::IceOptions(options) => {
                        // hardcoded by tribal knowledge to "trickle", but we want to negotiate other options, too
                        // see https://codeberg.org/iNPUTmice/Conversations/commit/fd4b8ba1885a9f6e24a87e47c3a6a730f9ed15f8
                        for option in options {
                            media_transport.add_ice_option(option);
                        }
                    }
                    SdpAttribute::IcePacing(_) => {}
                    SdpAttribute::IcePwd(s) => {
                        media_transport.set_pwd(s.clone());
                    }
                    SdpAttribute::IceUfrag(s) => {
                        media_transport.set_ufrag(s.clone());
                    }
                    SdpAttribute::Identity(_) => {}
                    SdpAttribute::ImageAttr(_) => {}
                    SdpAttribute::Inactive => {}
                    SdpAttribute::Label(_) => {}
                    SdpAttribute::MaxMessageSize(_) => {}
                    SdpAttribute::MaxPtime(_) => {}
                    SdpAttribute::Mid(name) => {
                        content.name = name.clone();
                    }
                    SdpAttribute::Msid(_) => {}
                    SdpAttribute::MsidSemantic(_) => {}
                    SdpAttribute::Ptime(_) => {}
                    SdpAttribute::Rid(_) => {}
                    SdpAttribute::Recvonly => {
                        if initiator {
                            content.senders = ContentCreator::Responder;
                        } else {
                            content.senders = ContentCreator::Initiator;
                        }
                    }
                    SdpAttribute::RemoteCandidate(_) => {}
                    SdpAttribute::Rtpmap(rtmap) => {
                        jingle
                            .get_payload_type(rtmap.payload_type)
                            .fill_from_sdp_rtpmap(rtmap);
                    }
                    SdpAttribute::Rtcp(_) => {}
                    SdpAttribute::Rtcpfb(fb) => {
                        // TODO use trait later
                        match fb.payload_type {
                            SdpAttributePayloadType::Wildcard => match fb.feedback_type {
                                SdpAttributeRtcpFbType::TrrInt => {
                                    jingle.add_rtcp_fb_trr_int(RtcpFbTrrInt::new_from_sdp(fb));
                                }
                                _ => {
                                    jingle.add_rtcp_fb(RtcpFb::new_from_sdp(fb));
                                }
                            },
                            SdpAttributePayloadType::PayloadType(payload_id) => {
                                let jingle_p_t: &mut JingleRtpSessionsPayloadType =
                                    jingle.get_payload_type(payload_id);
                                match fb.feedback_type {
                                    SdpAttributeRtcpFbType::TrrInt => {
                                        jingle_p_t
                                            .add_rtcp_fb_trr_int(RtcpFbTrrInt::new_from_sdp(fb));
                                    }
                                    _ => {
                                        jingle_p_t.add_rtcp_fb(RtcpFb::new_from_sdp(fb));
                                    }
                                }
                            }
                        }
                    }
                    SdpAttribute::RtcpMux => {
                        jingle.add_rtcp_mux();
                    }
                    SdpAttribute::RtcpMuxOnly => {}
                    SdpAttribute::RtcpRsize => {}
                    SdpAttribute::Sctpmap(_) => {}
                    SdpAttribute::SctpPort(_) => {}
                    SdpAttribute::Sendonly => {
                        if initiator {
                            content.senders = ContentCreator::Initiator;
                        } else {
                            content.senders = ContentCreator::Responder;
                        }
                    }
                    SdpAttribute::Sendrecv => {
                        content.senders = ContentCreator::Both;
                    }
                    SdpAttribute::Setup(s) => {
                        fingerprint.set_setup(s);
                    }
                    SdpAttribute::Simulcast(_) => {}
                    SdpAttribute::Ssrc(ssrc) => {
                        jingle.add_ssrc(ssrc);
                    }
                    SdpAttribute::SsrcGroup(semantics, ssrcs) => {
                        jingle.add_ssrc_group(JingleSsrcGroup::new_from_sdp(semantics, ssrcs));
                    }
                }
            }
            if fingerprint.is_set() {
                media_transport.add_fingerprint(fingerprint);
            }
            content.add_transport(media_transport);
            for sdp_bandwidth in media.get_bandwidth() {
                let jingle_bandwith = JingleRtpSessionsBandwidth::new_from_sdp(sdp_bandwidth);
                jingle.add_sdp_bandwith(jingle_bandwith.clone());
            }
            jingle.fill_from_payload_helper();
            jingle.fill_from_ssrc_helper();
            content.childs.push(JingleDes::Description(jingle));
            root.push(RootEnum::Content(content));
        }
        Ok(root)
    }

    pub fn to_sdp(root: &Root, initiator: bool) -> Result<SdpSession, SdpParserInternalError> {
        let sdp_origin = SdpOrigin {
            //TODO: really hardcode these??
            username: "-".to_string(),
            session_id: 2005859539484728435,
            session_version: 2,
            unicast_addr: ExplicitlyTypedAddress::Ip(std::net::IpAddr::V4(Ipv4Addr::LOCALHOST)),
        };
        let mut sdp = SdpSession::new(0, sdp_origin, "-".to_string());
        // timing values are always zero when the offer/answer model is used
        sdp.set_timing(SdpTiming { start: 0, stop: 0 });

        for root_entry in root.childs() {
            match root_entry {
                RootEnum::Group(jingle_group) => {
                    if let Err(e) = sdp.add_attribute(SdpAttribute::Group(jingle_group.to_sdp())) {
                        eprintln!("Could not add ContentGroup attribute to sdp: {}", e);
                        return Err(e);
                    } else {
                        //hardcoded because webrtc needs this but there is no xep for it!
                        //only add this if we use xep-0338 content groups
                        sdp.add_attribute(SdpAttribute::MsidSemantic(SdpAttributeMsidSemantic {
                            semantic: " WMS".to_string(),
                            msids: vec!["stream".to_string()],
                        }))?;
                    }
                }
                RootEnum::Content(jingle_content) => {
                    // first of all: create media element...
                    let mut media_type: Option<SdpMediaValue> = None;
                    for child in &jingle_content.childs {
                        match child {
                            JingleDes::Transport(_) => {}
                            JingleDes::Description(rtp_session) => {
                                media_type = Some(rtp_session.media().to_sdp());
                            }
                            JingleDes::Invalid => continue,
                        }
                    }
                    let direction = match jingle_content.senders {
                        ContentCreator::Initiator => {
                            if initiator {
                                SdpAttribute::Sendonly
                            } else {
                                SdpAttribute::Recvonly
                            }
                        }
                        ContentCreator::Responder => {
                            if initiator {
                                SdpAttribute::Recvonly
                            } else {
                                SdpAttribute::Sendonly
                            }
                        }
                        ContentCreator::Both => SdpAttribute::Sendrecv,
                    };
                    if let Some(media_type) = media_type {
                        let mut media = SdpMedia::new(SdpMediaLine {
                            media: media_type,
                            port: 9, //port hardcoded by xep?
                            //hardcoded by xep? see also https://codeberg.org/iNPUTmice/Conversations/src/branch/master/src/main/java/eu/siacs/conversations/xmpp/jingle/SessionDescription.java#L28
                            port_count: 0, // hardcoded
                            proto: SdpProtocolValue::UdpTlsRtpSavp,
                            formats: SdpFormatList::Integers(Vec::new()),
                        });

                        if let Err(e) = media.add_attribute(direction) {
                            eprintln!("Could not add Media to sdp: {}", e);
                            return Result::Err(e);
                        }

                        media.set_connection(SdpConnection {
                            address: ExplicitlyTypedAddress::Ip(IpAddr::V4(Ipv4Addr::UNSPECIFIED)),
                            ttl: None,
                            amount: None,
                        });

                        sdp.media.push(media);
                    } else {
                        return Err(SdpParserInternalError::Generic(
                            "No media found in jingle!".to_string(),
                        ));
                    }
                    let media = sdp.media.last_mut().unwrap();
                    let mut ice_options: Vec<String> = Vec::new();

                    // ...after that: fill media attributes
                    media.add_attribute(SdpAttribute::Mid(jingle_content.name.clone()))?;
                    for child in &jingle_content.childs {
                        match child {
                            JingleDes::Transport(transport) => {
                                // hardcoded by xep-0293 ??
                                media.add_attribute(SdpAttribute::Rtcp(SdpAttributeRtcp {
                                    port: 9,
                                    unicast_addr: Some(ExplicitlyTypedAddress::Ip(IpAddr::V4(
                                        Ipv4Addr::UNSPECIFIED,
                                    ))),
                                }))?;

                                if let Some(pwd) = transport.get_pwd() {
                                    media.add_attribute(SdpAttribute::IcePwd(pwd))?;
                                }
                                if let Some(ufrag) = transport.get_ufrag() {
                                    media.add_attribute(SdpAttribute::IceUfrag(ufrag))?;
                                }
                                for item in transport.items() {
                                    match item {
                                        JingleTransportItems::Fingerprint(fingerprint) => {
                                            media.add_attribute(SdpAttribute::Fingerprint(
                                                fingerprint.get_fingerprint()?,
                                            ))?;
                                            media.add_attribute(SdpAttribute::Setup(
                                                fingerprint.get_setup(),
                                            ))?;
                                        }
                                        JingleTransportItems::Candidate(candidate) => {
                                            media.add_attribute(SdpAttribute::Candidate(
                                                candidate.to_sdp(transport.get_ufrag())?,
                                            ))?;
                                        }
                                        JingleTransportItems::Trickle(_) => {
                                            ice_options.push("trickle".to_string());
                                        }
                                        JingleTransportItems::Renomination(_) => {
                                            ice_options.push("renomination".to_string());
                                        }
                                        JingleTransportItems::Invalid => {}
                                    }
                                }
                            }
                            JingleDes::Description(rtp_session) => {
                                for session_value in rtp_session.item() {
                                    if let Err(e) = match session_value {
                                        JingleRtpSessionsValue::PayloadType(payload_type) => {
                                            if let Err(e) =
                                                media.add_codec(payload_type.to_sdp_rtpmap())
                                            {
                                                eprintln!(
                                                    "Could not add media codec {} ({}) to sdp: {}",
                                                    payload_type.id(),
                                                    match &payload_type.name() {
                                                        Some(name) => name,
                                                        None => "",
                                                    },
                                                    e
                                                );
                                                return Err(e);
                                            }

                                            for param in payload_type.parameter() {
                                                match &param {
                                                    JingleRtpSessionsPayloadTypeValue::Parameter(_) => (), // will be handled by to_sdp_fmtp() below
                                                    JingleRtpSessionsPayloadTypeValue::RtcpFb(fb) => {
                                                        media.add_attribute(SdpAttribute::Rtcpfb(fb.to_sdp(SdpAttributePayloadType::PayloadType(payload_type.id()))))?;
                                                    },
                                                    JingleRtpSessionsPayloadTypeValue::RtcpFbTrrInt(trr_int) => {
                                                        media.add_attribute(SdpAttribute::Rtcpfb(trr_int.to_sdp(SdpAttributePayloadType::PayloadType(payload_type.id()))))?;
                                                    },
                                                    JingleRtpSessionsPayloadTypeValue::Invalid => continue,
                                                }
                                            }

                                            if let Some(fmtp) = payload_type.to_sdp_fmtp()? {
                                                media.add_attribute(SdpAttribute::Fmtp(fmtp))?
                                            }

                                            Ok(())
                                        }
                                        JingleRtpSessionsValue::Bandwidth(bandwidth) => {
                                            media.add_bandwidth(bandwidth.to_sdp());
                                            Ok(())
                                        }
                                        JingleRtpSessionsValue::RtcpMux => {
                                            media.add_attribute(SdpAttribute::RtcpMux)
                                        }
                                        JingleRtpSessionsValue::RtcpFb(fb) => {
                                            media.add_attribute(SdpAttribute::Rtcpfb(
                                                fb.to_sdp(SdpAttributePayloadType::Wildcard),
                                            ))
                                        }
                                        JingleRtpSessionsValue::RtcpFbTrrInt(trr_int) => media
                                            .add_attribute(SdpAttribute::Rtcpfb(
                                                trr_int.to_sdp(SdpAttributePayloadType::Wildcard),
                                            )),
                                        JingleRtpSessionsValue::Source(ssrc) => {
                                            for attribute in ssrc.to_sdp() {
                                                if let Err(e) = media
                                                    .add_attribute(SdpAttribute::Ssrc(attribute))
                                                {
                                                    eprintln!(
                                                        "Could not add Ssrc attribute to sdp: {}",
                                                        e
                                                    );
                                                    return Err(e);
                                                }
                                            }
                                            Ok(())
                                        }
                                        JingleRtpSessionsValue::SsrcGroup(ssrc_group) => {
                                            let (semantics, ssrcs) = ssrc_group.to_sdp();
                                            media.add_attribute(SdpAttribute::SsrcGroup(
                                                semantics, ssrcs,
                                            ))
                                        }
                                        JingleRtpSessionsValue::ExtmapAllowMixed => {
                                            media.add_attribute(SdpAttribute::ExtmapAllowMixed)
                                        }
                                        JingleRtpSessionsValue::RtpHdrext(hdrext) => media
                                            .add_attribute(SdpAttribute::Extmap(
                                                hdrext.to_sdp(initiator),
                                            )),
                                        JingleRtpSessionsValue::Invalid => Ok(()),
                                    } {
                                        eprintln!("Could not add attribute to sdp: {}", e);
                                        return Err(e);
                                    }
                                }
                            }
                            JingleDes::Invalid => continue,
                        }
                    }
                    if ice_options.is_empty() {
                        // hardcoded by tribal knowledge to "trickle"
                        media.add_attribute(SdpAttribute::IceOptions(
                            ["trickle"].iter().map(|s| s.to_string()).collect(),
                        ))?;
                    } else {
                        // use xep-gultsch (see https://codeberg.org/iNPUTmice/Conversations/commit/fd4b8ba1885a9f6e24a87e47c3a6a730f9ed15f8)
                        media.add_attribute(SdpAttribute::IceOptions(
                            ice_options.iter().map(|s| s.to_string()).collect(),
                        ))?;
                    }
                }
                RootEnum::Invalid => {}
            }
        }
        Ok(sdp)
    }
}
