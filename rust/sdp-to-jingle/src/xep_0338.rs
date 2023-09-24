use serde_derive::{Deserialize, Serialize};
use webrtc_sdp::attribute_type::{SdpAttributeGroup, SdpAttributeGroupSemantic};

// *** xep-0338
#[derive(Serialize, Deserialize)]
pub struct ContentGroup {
    #[serde(rename = "@xmlns", default)]
    xmlns: String,
    #[serde(rename = "@semantics")]
    semantics: GroupSemantics,
    content: Vec<GroupContent>,
}

impl ContentGroup {
    pub fn new_from_sdp(group: &SdpAttributeGroup) -> Self {
        let mut content = Vec::new();
        for tag in &group.tags {
            content.push(GroupContent::new(tag.to_string()));
        }
        Self {
            xmlns: "urn:xmpp:jingle:apps:grouping:0".to_string(),
            semantics: GroupSemantics::new_from_sdp(&group.semantics),
            content,
        }
    }

    pub fn to_sdp(&self) -> SdpAttributeGroup {
        let mut tags: Vec<String> = Vec::new();
        for group_content in &self.content {
            tags.push(group_content.get_tag())
        }
        SdpAttributeGroup {
            semantics: self.semantics.to_sdp(),
            tags,
        }
    }
}

// *** xep-0338
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "UPPERCASE")]
pub enum GroupSemantics {
    Ls,
    Fid,
    Srf,
    Anat,
    Fec,
    Ddp,
    Bundle,
}

impl GroupSemantics {
    pub fn new_from_sdp(semantics: &SdpAttributeGroupSemantic) -> Self {
        match semantics {
            SdpAttributeGroupSemantic::LipSynchronization => Self::Ls,
            SdpAttributeGroupSemantic::FlowIdentification => Self::Fid,
            SdpAttributeGroupSemantic::SingleReservationFlow => Self::Srf,
            SdpAttributeGroupSemantic::AlternateNetworkAddressType => Self::Anat,
            SdpAttributeGroupSemantic::ForwardErrorCorrection => Self::Fec,
            SdpAttributeGroupSemantic::DecodingDependency => Self::Ddp,
            SdpAttributeGroupSemantic::Bundle => Self::Bundle,
        }
    }

    pub fn to_sdp(&self) -> SdpAttributeGroupSemantic {
        match self {
            Self::Ls => SdpAttributeGroupSemantic::LipSynchronization,
            Self::Fid => SdpAttributeGroupSemantic::FlowIdentification,
            Self::Srf => SdpAttributeGroupSemantic::SingleReservationFlow,
            Self::Anat => SdpAttributeGroupSemantic::AlternateNetworkAddressType,
            Self::Fec => SdpAttributeGroupSemantic::ForwardErrorCorrection,
            Self::Ddp => SdpAttributeGroupSemantic::DecodingDependency,
            Self::Bundle => SdpAttributeGroupSemantic::Bundle,
        }
    }
}

// *** xep-0338
#[derive(Serialize, Deserialize, Default)]
#[serde(rename = "content")]
pub struct GroupContent {
    #[serde(rename = "@name")]
    name: String,
}

impl GroupContent {
    pub fn new(tag: String) -> Self {
        Self { name: tag }
    }

    pub fn get_tag(&self) -> String {
        self.name.to_string()
    }
}
