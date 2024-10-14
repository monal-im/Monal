use clap::Parser;
use std::fs;
use std::io::Read;

use monal_html_parser::MonalHtmlParser;

/// Parse the given html file for text contents or attributes of given selector
#[derive(Parser)]
struct Cli {
    /// The path to the file to read (use '-' for stdin)
    path: std::path::PathBuf,
    /// The selector to look for
    selector: String,
    /// An optional attribute name to return (omit to return text contents)
    attribute: Option<String>,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Cli::parse();
    println!(
        "path: {:?}, selector: {:?}, attribute: {:?}",
        args.path, args.selector, args.attribute
    );
    let mut html = String::new();
    if args.path.as_os_str().to_str() == Some("-") {
        std::io::stdin().lock().read_to_string(&mut html)?;
    } else {
        html = fs::read_to_string(args.path)?;
    }
    let parser = MonalHtmlParser::new(html);
    let found = parser.select(args.selector, args.attribute);
    println!("result: {:?}", found);
    Ok(())
}
