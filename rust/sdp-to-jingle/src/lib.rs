use jingle::Root;
use webrtc_sdp::parse_sdp;
use xep_0167::JingleRtpSessions;

mod jingle;
mod xep_0167;
mod xep_0176;
mod xep_0293;
mod xep_0294;
mod xep_0320;
mod xep_0338;
mod xep_0339;

pub fn sdp_str_to_jingle_str(sdp_str: &str, initiator: bool) -> Option<String> {
    let sdp_session = match parse_sdp(sdp_str, true) {
        Err(e) => {
            eprintln!("Could not parse sdpstring: {}", e);
            return None;
        }
        Ok(sdp) => sdp,
    };

    for warning in &sdp_session.warnings {
        eprintln!("mozilla sdp parser warning: {}", warning);
    }

    let jingle = match JingleRtpSessions::from_sdp(&sdp_session, initiator) {
        Err(e) => {
            eprintln!("Could not convert sdp to jingle: {}", e);
            return None;
        }
        Ok(jingle) => jingle,
    };

    match quick_xml::se::to_string(&jingle) {
        Err(e) => {
            eprintln!("Could not serialize jingle to xmlstring: {}", e);
            None
        }
        Ok(jingle_xml) => Some(jingle_xml),
    }
}

pub fn jingle_str_to_sdp_str(jingle_str: &str, initiator: bool) -> Option<String> {
    let jingle: Root = match quick_xml::de::from_str(jingle_str) {
        Err(e) => {
            eprintln!("Could not parse xmlstring: {}", e);
            return None;
        }
        Ok(j) => j,
    };

    let sdp = match JingleRtpSessions::to_sdp(&jingle, initiator) {
        Err(e) => {
            eprintln!("Could not convert jingle to sdp: {}", e);
            return None;
        }
        Ok(j) => j,
    };

    Some(
        sdp.to_string()
            .lines()
            .collect::<Vec<&str>>()
            .join("\r\n")
            .to_string()
            + "\r\n",
    )
}

pub(crate) fn is_none_or_default<T>(value: &Option<T>) -> bool
where
    T: Default + std::cmp::PartialEq,
{
    if let Some(inner_value) = value {
        return *inner_value == T::default();
    }
    true
}
