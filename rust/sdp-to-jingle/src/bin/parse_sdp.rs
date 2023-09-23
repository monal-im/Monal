use std::io;
use std::io::Read;

use sdp_to_jingle::sdp_str_to_jingle_str;

fn main() -> io::Result<()> {
    let mut sdp = String::new();
    std::io::stdin().lock().read_to_string(&mut sdp)?;
    let xml = sdp_str_to_jingle_str(sdp.as_str(), true).unwrap_or_else(|| "None".to_string());
    println!("{}", xml);
    Ok(())
}
