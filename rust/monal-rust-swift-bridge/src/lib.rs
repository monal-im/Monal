use crate::ffi::rust_panic_handler;
use monal_html_parser::MonalHtmlParser;
use monal_xml_parser::{MonalXmlStreamParser, MonalXmlStreamParserResult};

// #[swift_bridge::bridge]
// mod ffi_i {
//     pub enum MonalXmlStreamParserResultX {
//         // Start((String, String, Vec<(String, String)>)),
//         // End((String, String)),
//         Text(String),
//         CData(String),
//         NeedMoreData,
//     }
// }
// 
// use ffi_i::MonalXmlStreamParserResultX;

#[swift_bridge::bridge]
pub mod ffi {
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
        pub fn select(
            &self,
            selector: String,
            atrribute: Option<String>,
        ) -> Vec<String>;
    }
    
    //rust struct exported from rust to swift
    extern "Rust" {
        type MonalXmlStreamParser;
        #[swift_bridge(init)]
        pub fn new() -> MonalXmlStreamParser;
        pub fn feed(&mut self, chunk: &str);
        pub fn poll(&mut self) -> Result<MonalXmlStreamParserResultWrapper, String>;
    }
    
    //enum wrapper
    //TODO: autogenerate this (@friedrichaltheide)
    extern "Rust" {
        pub enum MonalXmlStreamParserResultWrapper {
            Start((String, String, Vec<(String, String)>)),
            End((String, String)),
            Text(String),
            CData(String),
            NeedMoreData,
        }
    }
    
    //exported from our internal swift helper to rust
    extern "Swift" {
        fn rust_panic_handler(text: String, backtrace: String);
    }
}

//from implementation for enum wrapper
//TODO: autogenerate this (@friedrichaltheide)
pub impl From<MonalXmlStreamParserResult> for MonalXmlStreamParserResultWrapper {
    pub fn from(item: MonalXmlStreamParserResult) -> Self {
        match orig {
            MonalXmlStreamParserResult::Start((String, String, Vec<(String, String)>)) => MonalXmlStreamParserResultWrapper::Start((String, String, Vec<(String, String)>)),
            MonalXmlStreamParserResult::End((String, String)) => MonalXmlStreamParserResultWrapper::End((String, String)),
            MonalXmlStreamParserResult::Text(String) => MonalXmlStreamParserResultWrapper::Text(String),
            MonalXmlStreamParserResult::CData(String) => MonalXmlStreamParserResultWrapper::CData(String),
            MonalXmlStreamParserResult::NeedMoreData => MonalXmlStreamParserResultWrapper::NeedMoreData,
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
