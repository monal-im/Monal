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
            eprintln!("Could not parse sdp: {}", e);
            return None;
        }
        Ok(sdp) => sdp,
    };

    for warning in &sdp_session.warnings {
        eprintln!("sdp parser warning: {}", warning);
    }

    let jingle = JingleRtpSessions::from_sdp(&sdp_session, initiator);

    match quick_xml::se::to_string(&jingle) {
        Err(e) => {
            eprintln!("Could not serialize jingle to xml: {}", e);
            None
        }
        Ok(jingle_xml) => Some(jingle_xml),
    }
}

pub fn jingle_str_to_sdp_str(jingle_str: &str, initiator: bool) -> Option<String> {
    let jingle: Root = match quick_xml::de::from_str(jingle_str) {
        Err(e) => {
            eprintln!("Error parsing xml: {}", e);
            return None;
        }
        Ok(j) => j,
    };

    let sdp = match JingleRtpSessions::to_sdp(&jingle, initiator) {
        Err(e) => {
            eprintln!("Error converting parsed xml into sdp: {}", e);
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
