use quick_xml::events::Event;
use quick_xml::NsReader;
use quick_xml::name::ResolveResult;
use std::collections::VecDeque;
use std::str;

pub enum MonalXmlStreamParserResult {
    Start((String, String, Vec<(String, String)>)),
    End((String, String)),
    Text(String),
    CData(String),
    NeedMoreData,
}

pub struct MonalXmlStreamParser {
    reader: NsReader<VecDeque<u8>>,
    buffer: Vec<u8>,
}

impl MonalXmlStreamParser {
    pub fn new() -> Self {
        let mut reader = NsReader::from_reader(VecDeque::new());
        reader.config_mut().allow_dangling_amp = false;
        reader.config_mut().allow_unmatched_ends = false;
        reader.config_mut().check_comments = false;
        reader.config_mut().check_end_names = true;
        reader.config_mut().expand_empty_elements = true;
        reader.config_mut().trim_markup_names_in_closing_tags = true;
        reader.config_mut().trim_text_start = false;
        reader.config_mut().trim_text_end = false;
        Self {
            reader,
            buffer: Vec::new(),
        }
    }

    pub fn feed(&mut self, chunk: &str) {
        self.reader.get_mut().extend(chunk.as_bytes());
    }
    
    pub fn poll(&mut self) -> Result<MonalXmlStreamParserResult, String> {
        let retval = match self.reader.read_resolved_event_into(&mut self.buffer) {
            Ok((nsresult, Event::Start(start))) => {
                let name = str::from_utf8(start.name().local_name().as_ref()).map_err(|e| e.to_string())?.to_string();
                let ns = ns_to_string(nsresult)?;
                
                let mut attrs = vec![];
                for attr in start.attributes().with_checks(true) {
                    let attr = attr.map_err(|e| e.to_string())?;
                    let key = str::from_utf8(attr.key.local_name().as_ref()).map_err(|e| e.to_string())?.to_string();
                    let val = attr.unescape_value().map_err(|e| e.to_string())?.to_string();
                    attrs.push((key, val));
                }

                Ok(MonalXmlStreamParserResult::Start((name, ns, attrs)))
            }

            Ok((nsresult, Event::End(end))) => {
                let name = str::from_utf8(end.name().local_name().as_ref()).map_err(|e| e.to_string())?.to_string();
                let ns = ns_to_string(nsresult)?;
                Ok(MonalXmlStreamParserResult::End((name, ns)))
            }

            Ok((_, Event::Text(text))) => {
                let cow = text.xml10_content().map_err(|e| e.to_string())?;
                Ok(MonalXmlStreamParserResult::Text(cow.into_owned()))
            }

            Ok((_, Event::CData(cdata))) => {
                let cow = cdata.xml10_content().map_err(|e| e.to_string())?;
                Ok(MonalXmlStreamParserResult::CData(cow.into_owned()))
            }
            

            Ok((_, Event::Eof)) => Ok(MonalXmlStreamParserResult::NeedMoreData),     // this feed's cycle is complete, no more data to parse

            Err(err) => {
                Err(format!("XML parsing error: {}", err.to_string()))
            }

            catchall => {
                panic!("Unexpected xml parsing event: {:?}", catchall);
            }
        };
        
        self.buffer.clear();        // clear temporary buffer used by read_resolved_event_into()
        
        // prevent memory leak by removing consumed bytes from our VecDeque
        let consumed = self.reader.buffer_position();
        if consumed > 0 {
            let buf = self.reader.get_mut();
            for _ in 0..consumed {
                buf.pop_front();
            }
        }
        
        retval
    }
}

fn ns_to_string(nsresult: ResolveResult) -> Result<String, String> {
    match nsresult {
        ResolveResult::Bound(ns) => Ok(String::from_utf8(ns.as_ref().to_vec()).map_err(|e| e.to_string())?),
        ResolveResult::Unbound => Ok("".to_string()),
        ResolveResult::Unknown(buf) => Err(format!("Tried to use unbound namespace: {}", String::from_utf8_lossy(&buf))),
    }
}
