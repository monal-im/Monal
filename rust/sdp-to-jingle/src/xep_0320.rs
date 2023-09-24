use serde_derive::{Deserialize, Serialize};
use webrtc_sdp::{
    attribute_type::{SdpAttributeFingerprint, SdpAttributeFingerprintHashType, SdpAttributeSetup},
    error::SdpParserInternalError,
};

// *** xep-0320
#[derive(Serialize, Deserialize, Default)]
pub struct JingleTranportFingerprint {
    #[serde(rename = "@xmlns", default)]
    xmlns: String,
    #[serde(rename = "@hash")]
    hash: String,
    #[serde(rename = "@setup")]
    setup: JingleTranportFingerprintSetup,
    #[serde(rename = "$value")]
    fingerprint: String,
    #[serde(skip)]
    is_set: bool, //used only for sdp2jingle, always false for jingle2sdp
}

impl JingleTranportFingerprint {
    pub fn new() -> Self {
        Self {
            xmlns: "urn:xmpp:jingle:apps:dtls:0".to_string(),
            ..Default::default()
        }
    }

    pub fn set_fingerprint(&mut self, sdp_a_fingerprint: &SdpAttributeFingerprint) {
        self.hash = sdp_a_fingerprint.hash_algorithm.to_string();
        self.fingerprint = sdp_a_fingerprint
            .fingerprint
            .iter()
            .map(|byte| format!("{:02X}", byte))
            .collect::<Vec<String>>()
            .join(":");
        self.is_set = true;
    }

    pub fn get_fingerprint(&self) -> Result<SdpAttributeFingerprint, SdpParserInternalError> {
        // could also use this fn body, but that would tie the fingerprint format in sdp and jingle together:
        // let hash_algorithm = SdpAttributeFingerprintHashType::try_from_name(self.hash.as_str())?;
        // let bytes = hash_algorithm.parse_octets(self.fingerprint.as_str())?;
        // SdpAttributeFingerprint::try_from((hash_algorithm, bytes))
        Ok(SdpAttributeFingerprint {
            fingerprint: self
                .fingerprint
                .split(':')
                .collect::<Vec<&str>>()
                .iter()
                .map(|hex| u8::from_str_radix(hex, 16))
                .collect::<Result<Vec<u8>, _>>()
                .unwrap(),
            hash_algorithm: SdpAttributeFingerprintHashType::try_from_name(self.hash.as_str())?,
        })
    }

    pub fn set_setup(&mut self, sdp: &SdpAttributeSetup) {
        self.setup = JingleTranportFingerprintSetup::from_sdp(sdp);
        self.is_set = true;
    }

    pub fn get_setup(&self) -> SdpAttributeSetup {
        self.setup.to_sdp()
    }

    pub fn is_set(&self) -> bool {
        self.is_set
    }
}

// *** xep-0320
#[derive(Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum JingleTranportFingerprintSetup {
    Active,
    Passive,
    #[default]
    Actpass,
    //Role, // not part of XEP 0320 XML schemas but used inside the XEP
    HoldConn,
}

impl JingleTranportFingerprintSetup {
    pub fn from_sdp(sdp: &SdpAttributeSetup) -> Self {
        match sdp {
            SdpAttributeSetup::Active => Self::Active,
            SdpAttributeSetup::Actpass => Self::Actpass,
            SdpAttributeSetup::Holdconn => Self::HoldConn,
            SdpAttributeSetup::Passive => Self::Passive,
        }
    }

    pub fn to_sdp(&self) -> SdpAttributeSetup {
        match self {
            Self::Active => SdpAttributeSetup::Active,
            Self::Actpass => SdpAttributeSetup::Actpass,
            Self::HoldConn => SdpAttributeSetup::Holdconn,
            Self::Passive => SdpAttributeSetup::Passive,
        }
    }
}
