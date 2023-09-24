use serde_derive::{Deserialize, Serialize};
use webrtc_sdp::attribute_type::{SdpAttributeDirection, SdpAttributeExtmap};

use crate::{
    jingle::{GenericParameter, GenericParameterEnum},
    xep_0167::ContentCreator,
};

// *** xep-0294
#[derive(Serialize, Deserialize)]
pub struct JingleHdrext {
    #[serde(rename = "@xmlns", default)]
    xmlns: String,
    #[serde(rename = "@id")]
    id: u16,
    #[serde(rename = "@uri")]
    uri: String,
    #[serde(rename = "@senders", skip_serializing_if = "Option::is_none")]
    senders: Option<ContentCreator>,
    #[serde(rename = "$value", skip_serializing_if = "Vec::is_empty", default)]
    parameter: Vec<GenericParameterEnum>,
}

impl JingleHdrext {
    pub fn new_from_sdp(initiator: bool, entry: &SdpAttributeExtmap) -> Self {
        let parameter_vec: Vec<GenericParameterEnum>;
        if let Some(attributes) = &entry.extension_attributes {
            parameter_vec = GenericParameter::parse_parameter_string(attributes)
                .into_iter()
                .map(GenericParameterEnum::Parameter)
                .collect::<Vec<GenericParameterEnum>>()
        } else {
            parameter_vec = Vec::new();
        }
        Self {
            xmlns: "urn:xmpp:jingle:apps:rtp:rtp-hdrext:0".to_string(),
            id: entry.id,
            uri: entry.url.to_string(),
            senders: entry.direction.as_ref().map(|direction| match direction {
                SdpAttributeDirection::Recvonly => {
                    if initiator {
                        ContentCreator::Responder
                    } else {
                        ContentCreator::Initiator
                    }
                }
                SdpAttributeDirection::Sendonly => {
                    if initiator {
                        ContentCreator::Initiator
                    } else {
                        ContentCreator::Responder
                    }
                }
                SdpAttributeDirection::Sendrecv => ContentCreator::Both,
            }),
            parameter: parameter_vec,
        }
    }

    pub fn to_sdp(&self, initiator: bool) -> SdpAttributeExtmap {
        SdpAttributeExtmap {
            id: self.id,
            url: self.uri.clone(),
            direction: self.senders.as_ref().map(|direction| match direction {
                ContentCreator::Initiator => {
                    if initiator {
                        SdpAttributeDirection::Sendonly
                    } else {
                        SdpAttributeDirection::Recvonly
                    }
                }
                ContentCreator::Responder => {
                    if initiator {
                        SdpAttributeDirection::Recvonly
                    } else {
                        SdpAttributeDirection::Sendonly
                    }
                }
                ContentCreator::Both => SdpAttributeDirection::Sendrecv,
            }),
            extension_attributes: if self.parameter.is_empty() {
                None
            } else {
                Some(GenericParameter::create_parameter_string(
                    &self
                        .parameter
                        .clone()
                        .into_iter()
                        .map(|p| match p {
                            GenericParameterEnum::Parameter(p) => p,
                        })
                        .collect::<Vec<GenericParameter>>(),
                ))
            },
        }
    }
}
