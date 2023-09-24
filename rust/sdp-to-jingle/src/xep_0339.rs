use serde_derive::{Deserialize, Serialize};
use webrtc_sdp::attribute_type::{SdpAttributeSsrc, SdpSsrcGroupSemantic};

use crate::jingle::{GenericParameter, GenericParameterEnum};

// *** xep-0339
#[derive(Serialize, Deserialize, Clone)]
pub struct JingleSsrc {
    #[serde(rename = "@xmlns", default)]
    xmlns: String,
    #[serde(rename = "@ssrc")]
    id: u32,
    #[serde(rename = "$value", skip_serializing_if = "Vec::is_empty", default)]
    parameter: Vec<GenericParameterEnum>,
}

impl JingleSsrc {
    pub fn new(id: u32) -> Self {
        Self {
            xmlns: "urn:xmpp:jingle:apps:rtp:ssma:0".to_string(),
            id,
            parameter: Vec::new(),
        }
    }

    pub fn add_parameter(&mut self, name: &str, value: Option<String>) {
        self.parameter
            .push(GenericParameterEnum::Parameter(GenericParameter::new(
                name.to_string(),
                value,
            )));
    }

    pub fn to_sdp(&self) -> Vec<SdpAttributeSsrc> {
        let mut retval: Vec<SdpAttributeSsrc> = Vec::new();
        for entry in &self.parameter {
            retval.push(SdpAttributeSsrc {
                id: self.id,
                attribute: Some(match entry {
                    GenericParameterEnum::Parameter(p) => p.name().to_string(),
                }),
                value: match entry {
                    GenericParameterEnum::Parameter(p) => p,
                }
                .value()
                .map(|value| value.to_string()),
            });
        }
        retval
    }
}

// *** xep-0339
#[derive(Serialize, Deserialize)]
pub struct JingleSsrcGroup {
    #[serde(rename = "@xmlns", default)]
    xmlns: String,
    #[serde(rename = "@semantics")]
    semantics: SsrcGroupSemantics,
    #[serde(rename = "source", skip_serializing_if = "Vec::is_empty")]
    sources: Vec<u32>,
}

impl JingleSsrcGroup {
    pub fn new_from_sdp(semantics: &SdpSsrcGroupSemantic, sources: &Vec<SdpAttributeSsrc>) -> Self {
        let semantics = match semantics {
            SdpSsrcGroupSemantic::Duplication => SsrcGroupSemantics::Dup,
            SdpSsrcGroupSemantic::FlowIdentification => SsrcGroupSemantics::Fid,
            SdpSsrcGroupSemantic::ForwardErrorCorrection => SsrcGroupSemantics::Fec,
            SdpSsrcGroupSemantic::ForwardErrorCorrectionFr => SsrcGroupSemantics::FecFr,
            SdpSsrcGroupSemantic::Sim => SsrcGroupSemantics::Sim,
        };
        let mut sources_vec: Vec<u32> = Vec::new();
        for ssrc in sources {
            sources_vec.push(ssrc.id);
        }
        Self {
            xmlns: "urn:xmpp:jingle:apps:rtp:ssma:0".to_string(),
            semantics,
            sources: sources_vec,
        }
    }

    pub fn to_sdp(&self) -> (SdpSsrcGroupSemantic, Vec<SdpAttributeSsrc>) {
        let semantics = match &self.semantics {
            SsrcGroupSemantics::Dup => SdpSsrcGroupSemantic::Duplication,
            SsrcGroupSemantics::Fid => SdpSsrcGroupSemantic::FlowIdentification,
            SsrcGroupSemantics::Fec => SdpSsrcGroupSemantic::ForwardErrorCorrection,
            SsrcGroupSemantics::FecFr => SdpSsrcGroupSemantic::ForwardErrorCorrectionFr,
            SsrcGroupSemantics::Sim => SdpSsrcGroupSemantic::Sim,
        };
        let mut sources_vec: Vec<SdpAttributeSsrc> = Vec::new();
        for id in &self.sources {
            sources_vec.push(SdpAttributeSsrc {
                id: *id,
                attribute: None,
                value: None,
            });
        }
        (semantics, sources_vec)
    }
}

// *** xep-0339
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "UPPERCASE")]
pub enum SsrcGroupSemantics {
    Dup,
    Fid,
    Fec,
    #[serde(rename = "FEC-FR")]
    FecFr,
    Sim, //not defined in the IANA registry?? see https://www.iana.org/assignments/sdp-parameters/sdp-parameters.xhtml#sdp-parameters-17
}
