use scraper::{Html, Selector};

pub struct MonalHtmlParser {
    document: Html,
}

impl MonalHtmlParser {
    pub fn new(html: String) -> Self {
        let document = Html::parse_document(&html);
        MonalHtmlParser { document }
    }

    pub fn select(
        &self,
        selector: String,
        atrribute: Option<String>,
    ) -> Vec<String> {
        let mut retval = Vec::new();
        let sel = match Selector::parse(&selector) {
            Ok(value) => value,
            Err(error) => {
                eprintln!("Selector '{selector}' parse error: {error}");
                return retval;
            }
        };
        for element in self.document.select(&sel) {
            match atrribute {
                Some(ref attr) => {
                    if let Some(val) = element.attr(attr) {
                        retval.push(val.to_string())
                    }
                }
                None => retval.push(element.text().map(String::from).collect()),
            };
        }
        retval
    }
}
