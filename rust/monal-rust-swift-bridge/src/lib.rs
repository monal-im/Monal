use crate::ffi::rust_panic_handler;
use crate::ffi::MonalXmlStreamParserResultElement;
use crate::ffi::MonalXmlStreamParserResultWrapper;
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

    //html parser struct exported to swift
    extern "Rust" {
        type MonalHtmlParser;
        #[swift_bridge(init)]
        pub fn new(html: String) -> MonalHtmlParser;
        pub fn select(&self, selector: String, atrribute: Option<String>) -> Vec<String>;
    }

    //these structs and enums and their fields are accessible from swift AND rust
    //but: we cannot use simple tuples, which are not supported by swift-bridge
    //--> we use a struct and separate vectors for key und value pairs
    #[swift_bridge(swift_repr = "struct")]
    struct MonalXmlStreamParserResultElement {
        name: String,
        ns: String,
        attr_keys: Option<Vec<String>>,
        attr_values: Option<Vec<String>>,
    }
    enum MonalXmlStreamParserResultWrapper {
        Start(MonalXmlStreamParserResultElement),
        End(MonalXmlStreamParserResultElement),
        Text(String),
        CData(String),
        NeedMoreData,
        Skipped,
    }

    //wrapped xml parser struct exported to swift (wrapping needed because of circular references because of return type)
    extern "Rust" {
        type MonalXmlStreamParserWrapper;
        #[swift_bridge(init)]
        pub fn new() -> MonalXmlStreamParserWrapper;
        pub fn feed(&mut self, chunk: &str);
        pub fn poll(&mut self) -> Result<MonalXmlStreamParserResultWrapper, String>;
    }

    //exported from our internal swift helper to rust
    extern "Swift" {
        fn rust_panic_handler(text: String, backtrace: String);
    }
}

//this is a wrapper (and corresponding From implementation) for MonalXmlStreamParser and MonalXmlStreamParserResult
//it is needed because exposing the enum and inner struct in the ffi interface while using it in the
//monal-xml-parser lib creates a circular dependency that has to be broken up by this wrapper
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
impl From<MonalXmlStreamParserResult> for MonalXmlStreamParserResultWrapper {
    fn from(item: MonalXmlStreamParserResult) -> Self {
        match item {
            MonalXmlStreamParserResult::Start((name, ns, attrs)) => {
                let mut attr_keys = vec![];
                let mut attr_values = vec![];
                for entry in &attrs {
                    attr_keys.push(entry.0.clone());
                    attr_values.push(entry.1.clone());
                }
                MonalXmlStreamParserResultWrapper::Start(MonalXmlStreamParserResultElement {
                    name,
                    ns,
                    attr_keys: Some(attr_keys),
                    attr_values: Some(attr_values),
                })
            }
            MonalXmlStreamParserResult::End((name, ns)) => {
                MonalXmlStreamParserResultWrapper::End(MonalXmlStreamParserResultElement {
                    name,
                    ns,
                    attr_keys: None,
                    attr_values: None,
                })
            }
            MonalXmlStreamParserResult::Text(text) => MonalXmlStreamParserResultWrapper::Text(text),
            MonalXmlStreamParserResult::CData(cdata) => {
                MonalXmlStreamParserResultWrapper::CData(cdata)
            }
            MonalXmlStreamParserResult::NeedMoreData => {
                MonalXmlStreamParserResultWrapper::NeedMoreData
            }
            MonalXmlStreamParserResult::Skipped => MonalXmlStreamParserResultWrapper::Skipped,
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
