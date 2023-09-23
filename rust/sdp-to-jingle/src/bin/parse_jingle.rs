use std::io;
use std::io::Read;

use sdp_to_jingle::jingle_str_to_sdp_str;

fn main() -> io::Result<()> {
    let mut xml = String::new();
    std::io::stdin().lock().read_to_string(&mut xml)?;
    let sdp = jingle_str_to_sdp_str(xml.as_str(), true).unwrap_or_else(|| "None".to_string());
    println!("{}", sdp);
    Ok(())
}
