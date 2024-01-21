use serde_derive::{Deserialize, Serialize};
use webrtc_sdp::attribute_type::{
    SdpAttributePayloadType, SdpAttributeRtcpFb, SdpAttributeRtcpFbType,
};

use crate::jingle::{GenericParameter, GenericParameterEnum};

// *** xep-0293
#[derive(Serialize, Deserialize, Clone)]
pub struct RtcpFb {
    #[serde(rename = "@xmlns", default)]
    xmlns: String,
    #[serde(rename = "@type")]
    fb_type: RtcpFbType,
    #[serde(rename = "@subtype", skip_serializing_if = "Option::is_none")]
    subtype: Option<String>,
    #[serde(rename = "$value", skip_serializing_if = "Vec::is_empty", default)]
    parameter: Vec<GenericParameterEnum>,
}

impl RtcpFb {
    pub fn new_from_sdp(sdp: &SdpAttributeRtcpFb) -> Self {
        assert!(!matches!(sdp.feedback_type, SdpAttributeRtcpFbType::TrrInt));
        Self {
            xmlns: "urn:xmpp:jingle:apps:rtp:rtcp-fb:0".to_string(),
            fb_type: RtcpFbType::new_from_sdp(&sdp.feedback_type),
            subtype: if sdp.parameter.is_empty() {
                None
            } else {
                Some(sdp.parameter.clone())
            },
            parameter: GenericParameter::parse_parameter_string(&sdp.extra)
                .into_iter()
                .map(GenericParameterEnum::Parameter)
                .collect::<Vec<GenericParameterEnum>>(),
        }
    }

    pub fn to_sdp(&self, payload_type: SdpAttributePayloadType) -> SdpAttributeRtcpFb {
        SdpAttributeRtcpFb {
            payload_type,
            feedback_type: self.fb_type.to_sdp(),
            parameter: match &self.subtype {
                Some(subtype) => subtype.to_string(),
                None => "".to_string(),
            },
            extra: GenericParameter::create_parameter_string(
                &self
                    .parameter
                    .clone()
                    .into_iter()
                    .filter_map(|p| match p {
                        GenericParameterEnum::Parameter(p) => Some(p),
                        GenericParameterEnum::Invalid => None,
                    })
                    .collect::<Vec<GenericParameter>>(),
            ),
        }
    }
}

// *** xep-0293
#[derive(Serialize, Deserialize, Clone)]
pub struct RtcpFbTrrInt {
    #[serde(rename = "@xmlns", default)]
    xmlns: String,
    #[serde(rename = "@value", default)]
    value: u32,
}

impl RtcpFbTrrInt {
    pub fn new_from_sdp(sdp: &SdpAttributeRtcpFb) -> Self {
        assert!(matches!(sdp.feedback_type, SdpAttributeRtcpFbType::TrrInt));
        Self {
            xmlns: "urn:xmpp:jingle:apps:rtp:rtcp-fb:0".to_string(),
            value: sdp.parameter.parse().unwrap_or_default(),
        }
    }

    pub fn to_sdp(&self, payload_type: SdpAttributePayloadType) -> SdpAttributeRtcpFb {
        SdpAttributeRtcpFb {
            payload_type,
            feedback_type: SdpAttributeRtcpFbType::TrrInt,
            parameter: self.value.to_string(),
            extra: "".to_string(),
        }
    }
}

// *** xep-0293
#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "kebab-case")]
pub enum RtcpFbType {
    Ack,
    Ccm,
    Nack,
    TrrInt,
    //the following two don't seem to be registered at IANA: https://www.iana.org/assignments/sdp-parameters/sdp-parameters.xhtml#sdp-parameters-14
    #[serde(rename = "goog-remb")]
    //this is defined in https://datatracker.ietf.org/doc/html/draft-alvestrand-rmcat-remb-03
    Remb,
    TransportCc,
}

impl RtcpFbType {
    pub fn new_from_sdp(sdp: &SdpAttributeRtcpFbType) -> Self {
        match sdp {
            SdpAttributeRtcpFbType::Ack => Self::Ack,
            SdpAttributeRtcpFbType::Ccm => Self::Ccm,
            SdpAttributeRtcpFbType::Nack => Self::Nack,
            SdpAttributeRtcpFbType::TrrInt => Self::TrrInt,
            SdpAttributeRtcpFbType::Remb => Self::Remb,
            SdpAttributeRtcpFbType::TransCc => Self::TransportCc,
        }
    }

    pub fn to_sdp(&self) -> SdpAttributeRtcpFbType {
        match self {
            Self::Ack => SdpAttributeRtcpFbType::Ack,
            Self::Ccm => SdpAttributeRtcpFbType::Ccm,
            Self::Nack => SdpAttributeRtcpFbType::Nack,
            Self::TrrInt => SdpAttributeRtcpFbType::TrrInt,
            Self::Remb => SdpAttributeRtcpFbType::Remb,
            Self::TransportCc => SdpAttributeRtcpFbType::TransCc,
        }
    }
}
