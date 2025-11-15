use crate::ffi::rust_panic_handler;
use monal_html_parser::MonalHtmlParser;
use monal_xml_parser::{MonalXmlStreamParser, MonalXmlStreamParserResult};

#[swift_bridge::bridge]
mod ffi {
    //simple functions exported from rust to swift
    extern "Rust" {
        pub fn install_panichandler();
        pub fn trigger_panic();
        pub fn sdp_str_to_jingle_str(sdp_str: String, initiator: bool) -> Option<String>;
        pub fn jingle_str_to_sdp_str(jingle_str: String, initiator: bool) -> Option<String>;
    }

    //rust struct exported from rust to swift
    extern "Rust" {
        type MonalHtmlParser;
        #[swift_bridge(init)]
        pub fn new(html: String) -> MonalHtmlParser;
        pub fn select(&self, selector: String, atrribute: Option<String>) -> Vec<String>;
    }

    //rust struct exported from rust to swift
    extern "Rust" {
        type MonalXmlStreamParserWrapper;
        #[swift_bridge(init)]
        pub fn new() -> MonalXmlStreamParserWrapper;
        pub fn feed(&mut self, chunk: &str);
        pub fn poll(&mut self) -> Result<MonalXmlStreamParserResultWrapper, String>;
    }

    //enum wrapper
    //TODO: autogenerate this (@friedrichaltheide)
    extern "Rust" {
        type MonalXmlStreamParserResultWrapper;
    }

    //exported from our internal swift helper to rust
    extern "Swift" {
        fn rust_panic_handler(text: String, backtrace: String);
    }
}

pub enum MonalXmlStreamParserResultWrapper {
    Start((String, String, Vec<(String, String)>)),
    End((String, String)),
    Text(String),
    CData(String),
    NeedMoreData,
}

struct MonalXmlStreamParserWrapper(MonalXmlStreamParser);

impl MonalXmlStreamParserWrapper {
    pub fn new() -> MonalXmlStreamParserWrapper {
        Self(MonalXmlStreamParser::new())
    }
    pub fn feed(&mut self, chunk: &str) {
        self.0.feed(chunk)
    }
    pub fn poll(&mut self) -> Result<MonalXmlStreamParserResultWrapper, String> {
        match self.0.poll() {
            Ok(stream_parser) => Ok(stream_parser.into()),
            Err(e) => Err(e),
        }
    }
}

//from implementation for enum wrapper
//TODO: autogenerate this (@friedrichaltheide)
impl From<MonalXmlStreamParserResult> for MonalXmlStreamParserResultWrapper {
    fn from(item: MonalXmlStreamParserResult) -> Self {
        match item {
            MonalXmlStreamParserResult::Start((name, ns, attrs)) => {
                MonalXmlStreamParserResultWrapper::Start((name, ns, attrs))
            }
            MonalXmlStreamParserResult::End((name, ns)) => {
                MonalXmlStreamParserResultWrapper::End((name, ns))
            }
            MonalXmlStreamParserResult::Text(text) => MonalXmlStreamParserResultWrapper::Text(text),
            MonalXmlStreamParserResult::CData(cdata) => {
                MonalXmlStreamParserResultWrapper::CData(cdata)
            }
            MonalXmlStreamParserResult::NeedMoreData => {
                MonalXmlStreamParserResultWrapper::NeedMoreData
            }
        }
    }
}

pub fn install_panichandler() {
    monal_panic_handler::install_panic_handler(rust_panic_handler);
}

pub fn trigger_panic() {
    panic!("Dummy panic!");
}

pub fn sdp_str_to_jingle_str(sdp_str: String, initiator: bool) -> Option<String> {
    sdp_to_jingle::sdp_str_to_jingle_str(&sdp_str, initiator)
}

pub fn jingle_str_to_sdp_str(jingle_str: String, initiator: bool) -> Option<String> {
    sdp_to_jingle::jingle_str_to_sdp_str(&jingle_str, initiator)
}
