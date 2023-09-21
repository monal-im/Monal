use std::fs::read_to_string;

use webrtc_sdp::parse_sdp;

fn main() {
    let sdp_txt = read_to_string("./examplesSdp/SDP-Audio-Monal.txt").unwrap();

    match parse_sdp(&sdp_txt, true) {
        Err(e) => {
            println!("Could not read sdp: {}", e);
        }
        Ok(s) => {
            println!("{:?}", s);
        }
    };
}
