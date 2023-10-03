use std::time::{SystemTime, UNIX_EPOCH};

use serde_derive::{Deserialize, Serialize};
use webrtc_sdp::{
    address::Address,
    attribute_type::{
        SdpAttributeCandidate, SdpAttributeCandidateTransport, SdpAttributeCandidateType,
    },
    error::SdpParserInternalError,
};

use crate::xep_0320::JingleTranportFingerprint;

// *** xep-0176
#[derive(Serialize, Deserialize, Default)]
pub struct JingleTransport {
    #[serde(rename = "@xmlns", default)]
    xmlns: String,
    #[serde(rename = "@pwd", skip_serializing_if = "Option::is_none")]
    pwd: Option<String>,
    #[serde(rename = "@ufrag", skip_serializing_if = "Option::is_none")]
    ufrag: Option<String>,
    #[serde(rename = "$value", skip_serializing_if = "Vec::is_empty", default)]
    items: Vec<JingleTransportItems>,
}

impl JingleTransport {
    pub fn new() -> Self {
        Self {
            xmlns: "urn:xmpp:jingle:transports:ice-udp:1".to_string(),
            ..Default::default()
        }
    }

    pub fn get_pwd(&self) -> Option<String> {
        self.pwd.clone()
    }

    pub fn set_pwd(&mut self, pwd: String) {
        self.pwd = Some(pwd);
    }

    pub fn get_ufrag(&self) -> Option<String> {
        self.ufrag.clone()
    }

    pub fn set_ufrag(&mut self, ufrag: String) {
        self.ufrag = Some(ufrag);
    }

    pub fn add_fingerprint(&mut self, fingerprint: JingleTranportFingerprint) {
        self.items
            .push(JingleTransportItems::Fingerprint(fingerprint));
    }

    // see https://codeberg.org/iNPUTmice/Conversations/commit/fd4b8ba1885a9f6e24a87e47c3a6a730f9ed15f8
    pub fn add_ice_option(&mut self, option: &String) {
        match option.as_str() {
            "trickle" => {
                self.items
                    .push(JingleTransportItems::Trickle(JingleICEOptionTrickle {
                        xmlns: gultsch_ice_options_ns(),
                    }));
            }
            "renomination" => {
                self.items.push(JingleTransportItems::Renomination(
                    JingleICEOptionRenomination {
                        xmlns: gultsch_ice_options_ns(),
                    },
                ));
            }
            &_ => {
                eprintln!("*** Encountered unknown ice option: {}", option);
            }
        }
    }

    pub fn add_candidate(&mut self, candidate: JingleTransportCandidate) {
        self.items.push(JingleTransportItems::Candidate(candidate));
    }

    pub fn items(&self) -> &Vec<JingleTransportItems> {
        &self.items
    }
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum JingleTransportItems {
    Fingerprint(JingleTranportFingerprint),
    Candidate(JingleTransportCandidate),
    Trickle(JingleICEOptionTrickle),
    Renomination(JingleICEOptionRenomination),
    #[serde(other)]
    Invalid,
}

//the next two structs are only needed because quick-xml does not support xml namespaces

fn gultsch_ice_options_ns() -> String {
    "http://gultsch.de/xmpp/drafts/jingle/transports/ice-udp/option".to_string()
}

// *** xep-gultsch (see https://codeberg.org/iNPUTmice/Conversations/commit/fd4b8ba1885a9f6e24a87e47c3a6a730f9ed15f8)
#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "kebab-case")]
pub struct JingleICEOptionTrickle {
    #[serde(rename = "@xmlns", default = "gultsch_ice_options_ns")]
    xmlns: String,
}

// *** xep-gultsch (see https://codeberg.org/iNPUTmice/Conversations/commit/fd4b8ba1885a9f6e24a87e47c3a6a730f9ed15f8)
#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "kebab-case")]
pub struct JingleICEOptionRenomination {
    #[serde(rename = "@xmlns", default = "gultsch_ice_options_ns")]
    xmlns: String,
}

// *** xep-0176
#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "kebab-case")]
pub struct JingleTransportCandidate {
    #[serde(rename = "@xmlns", default)]
    xmlns: String,
    #[serde(rename = "@id")]
    id: Option<String>, // not given in sdp, entirely made up random value, this is required according to xep, but some clients don't set it
    #[serde(rename = "@component")]
    component: u32,
    #[serde(rename = "@foundation")]
    foundation: String,
    #[serde(rename = "@generation")]
    generation: u32,
    #[serde(rename = "@ip")]
    ip: String, // address: Address
    #[serde(rename = "@network", skip_serializing_if = "Option::is_none")]
    network: Option<String>,
    #[serde(rename = "@port")]
    port: u32,
    #[serde(rename = "@priority")]
    priority: u64,
    #[serde(rename = "@protocol")]
    protocol: String, // transport: SdpAttributeCandidateTransport
    #[serde(rename = "@rel-addr", skip_serializing_if = "Option::is_none")]
    raddr: Option<String>, // raddr: Option<Address>
    #[serde(rename = "@rel_port", skip_serializing_if = "Option::is_none")]
    rport: Option<u32>,
    #[serde(rename = "@type")]
    c_type: JingleTransportCandidateType,
}

impl JingleTransportCandidate {
    pub fn new_from_sdp(candidate: &SdpAttributeCandidate) -> Result<Self, SdpParserInternalError> {
        let id = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .subsec_nanos();
        Ok(Self {
            xmlns: "urn:xmpp:jingle:transports:ice-udp:1".to_string(),
            id: Some(format!("{}", id)),
            component: candidate.component,
            foundation: candidate.foundation.to_string(),
            generation: match candidate.generation {
                None => {
                    eprintln!("Faking a '0' for unspecified candidate generation!");
                    0 //xep-0176 says this is required, fake a 0 value
                }
                Some(generation) => generation,
            },
            ip: format!("{}", candidate.address),
            network: None, //hardcoded to None
            port: candidate.port,
            priority: candidate.priority,
            protocol: match candidate.transport {
                SdpAttributeCandidateTransport::Udp => "udp".to_string(),
                //SdpAttributeCandidateTransport::Tcp => "tcp".to_string(), //not specced in xep-0176
                _ => {
                    return Err(SdpParserInternalError::Generic(
                        "Encountered some candidate transport (like tcp) not specced in XEP-0176!"
                            .to_string(),
                    ));
                }
            },
            raddr: candidate.raddr.as_ref().map(|addr| format!("{}", addr)),
            rport: candidate.rport,
            c_type: JingleTransportCandidateType::new_from_sdp(&candidate.c_type),
        })
    }

    pub fn to_sdp(
        &self,
        ufrag: Option<String>,
    ) -> Result<SdpAttributeCandidate, SdpParserInternalError> {
        Ok(SdpAttributeCandidate {
            foundation: self.foundation.to_string(),
            component: self.component,
            transport: match self.protocol.as_str() {
                "udp" => Ok(SdpAttributeCandidateTransport::Udp),
                //"tcp" => Ok(SdpAttributeCandidateTransport::Tcp),
                _ => Err(SdpParserInternalError::Generic(
                    "Encountered some candidate transport (like tcp) not specced in XEP-0176!"
                        .to_string(),
                )),
            }?,
            priority: self.priority,
            address: match &self.ip.parse() {
                Ok(ip) => Address::Ip(*ip),
                Err(_) => Address::Fqdn(self.ip.to_string()),
            },
            port: self.port,
            c_type: self.c_type.to_sdp(),
            raddr: match &self.raddr {
                None => None,
                Some(addr) => match &addr.parse() {
                    Ok(ip) => Some(Address::Ip(*ip)),
                    Err(_) => Some(Address::Fqdn(addr.to_string())),
                },
            },
            rport: self.rport,
            tcp_type: None, //tcp transport is not specced in any xep
            generation: Some(self.generation),
            ufrag,
            networkcost: None,              //not specced in xep-0176
            unknown_extensions: Vec::new(), //not specced in xep-0176
        })
    }
}

// *** xep-0176
#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "lowercase")]
pub enum JingleTransportCandidateType {
    Host,
    Srflx,
    Prflx,
    Relay,
}

impl JingleTransportCandidateType {
    pub fn new_from_sdp(c_type: &SdpAttributeCandidateType) -> Self {
        match c_type {
            SdpAttributeCandidateType::Host => Self::Host,
            SdpAttributeCandidateType::Srflx => Self::Srflx,
            SdpAttributeCandidateType::Prflx => Self::Prflx,
            SdpAttributeCandidateType::Relay => Self::Relay,
        }
    }

    pub fn to_sdp(&self) -> SdpAttributeCandidateType {
        match self {
            Self::Host => SdpAttributeCandidateType::Host,
            Self::Srflx => SdpAttributeCandidateType::Srflx,
            Self::Prflx => SdpAttributeCandidateType::Prflx,
            Self::Relay => SdpAttributeCandidateType::Relay,
        }
    }
}
