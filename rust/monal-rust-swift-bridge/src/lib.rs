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
    
    #[swift_bridge(already_declared)]
    enum MonalXmlStreamParserResult {}
    
    //rust struct exported from rust to swift
    extern "Rust" {
        type MonalXmlStreamParser;
        #[swift_bridge(init)]
        pub fn new() -> MonalXmlStreamParser;
        pub fn feed(&mut self, chunk: &str);
        pub fn poll(&mut self) -> Result<MonalXmlStreamParserResult, String>;
    }
    // extern "Rust" {
    //     type MonalXmlStreamParserResult;
    // }
    
    // extern "Rust" {
    //     enum MonalEnum {
    //         // Start((String, String, Vec<(String, String)>)),
    //         // End((String, String)),
    //         Text(String),
    //         CData(String),
    //         NeedMoreData,
    //     }
    // }
    
    //exported from our internal swift helper to rust
    extern "Swift" {
        fn rust_panic_handler(text: String, backtrace: String);
    }
}

// impl XmlStreamParserDelegateTrait for XmlStreamParserDelegate {
// }

// pub fn call_delegate(d: &mut XmlStreamParserDelegate) {
//     d.text("bla".to_string());
// }

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
