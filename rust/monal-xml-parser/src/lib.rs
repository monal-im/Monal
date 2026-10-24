use bytes::Buf;
use rxml::{
    error::EndOrError, Context, Event, Options, Parse, Parser, WithOptions, XmlVersion, XMLNS_XML,
    XMLNS_XMLNS,
};
use std::collections::VecDeque;
use std::sync::{Arc, OnceLock};

//global context for namespace string sharing between different parsers/threads
static GLOBAL_CONTEXT: OnceLock<Arc<Context>> = OnceLock::new();
pub fn global_context() -> Arc<Context> {
    GLOBAL_CONTEXT
        .get_or_init(|| Arc::new(Context::new()))
        .clone()
}

//simple wrapper for VecDeque implementing the Buf trait
pub struct VecDequeBuf(VecDeque<u8>);
impl VecDequeBuf {
    pub fn new(deque: VecDeque<u8>) -> Self {
        Self(deque)
    }

    pub fn extend(&mut self, bytes: &[u8]) {
        self.0.extend(bytes);
    }
}
impl Buf for VecDequeBuf {
    fn remaining(&self) -> usize {
        self.0.len()
    }

    fn chunk(&self) -> &[u8] {
        self.0.as_slices().0
    }

    fn advance(&mut self, cnt: usize) {
        self.0.drain(..cnt);
    }
}

#[derive(Debug)]
pub enum MonalXmlStreamParserResult {
    XmlDeclaration(String),
    Start((String, String, Vec<(String, String)>)),
    End,
    Text(String),
    NeedMoreData,
}

pub struct MonalXmlStreamParser {
    parser: Parser,
    pending: VecDequeBuf,
}

impl MonalXmlStreamParser {
    pub fn new(capacity: usize, max_token_length: usize) -> Self {
        let mut parser = Parser::new();
        parser.set_text_buffering(true);
        Self {
            parser: Parser::with_options(Options {
                max_token_length,
                context: Some(global_context()),
            }),
            pending: VecDequeBuf::new(VecDeque::with_capacity(capacity)),
        }
    }

    pub fn feed(&mut self, chunk: &[u8]) {
        self.pending.extend(chunk);
    }

    pub fn poll(&mut self) -> Result<MonalXmlStreamParserResult, String> {
        match self.parser.parse_buf(&mut self.pending, false) {
            Ok(event) => {
                match event {
                    Some(Event::XmlDeclaration(_statistics, xml_version)) => match xml_version {
                        XmlVersion::V1_0 => Ok(MonalXmlStreamParserResult::XmlDeclaration(
                            "1.0".to_string(),
                        )),
                    },
                    Some(Event::StartElement(_statistics, (ns, ncname), attributes)) => {
                        // eprintln!(
                        //     "New xml parsing event: StartElement({:?}, {:?})",
                        //     (ns.clone(), ncname.clone()),
                        //     attributes
                        // );
                        let (_prefix, local) = ncname
                            .to_name()
                            .split_name()
                            .map_err(|e| format!("Error: {:?}", e))?;
                        let attrs = attributes
                            .iter()
                            .map(|((ns, name), value)| {
                                (
                                    if ns == XMLNS_XML {
                                        "xml:".to_owned() + name
                                    } else if ns == XMLNS_XMLNS {
                                        "xmlns:".to_owned() + name
                                    } else {
                                        name.to_string()
                                    },
                                    value.to_string(),
                                )
                            })
                            .collect();
                        Ok(MonalXmlStreamParserResult::Start((
                            local.to_string(),
                            ns.to_string(),
                            attrs,
                        )))
                    }
                    Some(Event::EndElement(_statistics)) => Ok(MonalXmlStreamParserResult::End),
                    Some(Event::Text(_statistics, text)) => {
                        Ok(MonalXmlStreamParserResult::Text(text))
                    }
                    None => Ok(MonalXmlStreamParserResult::NeedMoreData), // this feed's cycle is complete, no more data to parse
                }
            }
            Err(EndOrError::NeedMoreData) => {
                Ok(MonalXmlStreamParserResult::NeedMoreData) // this feed's cycle is complete, no more data to parse
            }
            Err(EndOrError::Error(e)) => Err(format!("Error: {:?}", e)),
        }
    }
}
