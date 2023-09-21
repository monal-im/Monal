use std::fmt::Write;

use serde_derive::{Deserialize, Serialize};

use crate::xep_0167::{Content, JingleRtpSessionsBandwidth, JingleRtpSessionsPayloadType};
use crate::xep_0293::{RtcpFb, RtcpFbTrrInt};
use crate::xep_0294::JingleHdrext;
use crate::xep_0338::ContentGroup;
use crate::xep_0339::{JingleSsrc, JingleSsrcGroup};

// *** global
#[derive(Serialize, Deserialize, Default)]
#[serde(rename = "root")]
pub struct Root {
    #[serde(rename = "$value", skip_serializing_if = "Vec::is_empty", default)]
    childs: Vec<RootEnum>,
}

impl Root {
    pub fn push(&mut self, element: RootEnum) {
        self.childs.push(element);
    }

    pub fn childs(&self) -> &Vec<RootEnum> {
        &self.childs
    }
}

// *** global
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RootEnum {
    Content(Content),
    Group(ContentGroup),
}

// *** global
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum JingleRtpSessionsValue {
    PayloadType(JingleRtpSessionsPayloadType),
    Bandwidth(JingleRtpSessionsBandwidth),
    RtcpMux,
    RtcpFb(RtcpFb),
    RtcpFbTrrInt(RtcpFbTrrInt),
    Source(JingleSsrc),
    SsrcGroup(JingleSsrcGroup),
    ExtmapAllowMixed,
    RtpHdrext(JingleHdrext),
}

// *** generic enum for multiple xeps (e.g. global)
#[derive(Serialize, Deserialize, Clone)]
#[serde(rename_all = "lowercase")]
pub enum GenericParameterEnum {
    Parameter(GenericParameter),
}

// *** generic struct for multiple xeps (e.g. global)
#[derive(Serialize, Deserialize, Clone)]
pub struct GenericParameter {
    #[serde(rename = "@name")]
    name: String,
    #[serde(rename = "@value", skip_serializing_if = "Option::is_none")]
    value: Option<String>,
}

impl GenericParameter {
    pub fn new(name: String, value: Option<String>) -> Self {
        Self { name, value }
    }

    pub fn name(&self) -> &str {
        &self.name
    }

    pub fn value(&self) -> Option<&str> {
        self.value.as_deref()
    }

    pub fn parse_parameter_string(attributes: &str) -> Vec<Self> {
        let mut parameters_vec: Vec<Self> = Vec::new();
        // first: split by space
        let splitted_vec = attributes.split(' ');
        for splitted_part in splitted_vec {
            if splitted_part.is_empty() {
                continue;
            }
            // second: split by equal sign
            let splitted_sub_part_vec = splitted_part.split('=');
            let mut parameter_name: String = "".to_string();
            let mut parameter_value: Option<String> = None;
            for (i, value) in splitted_sub_part_vec.enumerate() {
                if i == 0 {
                    parameter_name = value.to_string();
                } else if i == 1 {
                    parameter_value = Some(value.to_string())
                } else {
                    unreachable!() //should never happen
                }
            }
            parameters_vec.push(Self::new(parameter_name, parameter_value));
        }
        parameters_vec
    }

    pub fn create_parameter_string(parameters: &Vec<Self>) -> String {
        let mut retval: String = "".to_owned();
        for param in parameters {
            if !retval.is_empty() {
                retval.push(' ');
            }
            match &param.value {
                Some(value) => write!(retval, "{}={}", param.name, value).unwrap(),
                None => write!(retval, "{}", param.name).unwrap(),
            }
        }
        retval
    }
}
