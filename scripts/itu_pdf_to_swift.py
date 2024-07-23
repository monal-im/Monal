#!/usr/bin/env python3
import requests
import io
from pypdf import PdfReader
import re
import logging

logging.basicConfig(level=logging.DEBUG, format="%(asctime)s [%(levelname)-7s] %(name)s {%(threadName)s} %(filename)s:%(lineno)d: %(message)s")
logger = logging.getLogger(__name__)

class Quicksy_Country:
    def __init__(self, name, code, pattern):
        self.name = name
        self.code = code
        self.pattern = pattern
    
    def __repr__(self):
        return f"Quicksy_Country(name: NSLocalizedString(\"{self.name}\", comment:\"quicksy country\"), code: \"{self.code}\", pattern: \"{self.pattern}\") ,"

def parse_pdf(pdf_data):
    country_regex = re.compile(r'^(?P<country>[^0-9]+)[ ]{32}(?P<code>[0-9]+)[ ]{32}(?P<international_prefix>.+)[ ]{32}(?P<national_prefix>.+)[ ]{32}(?P<format>.+ digits)[ ]{32}(?P<end>.*)$')
    country_end_regex = re.compile(r'^(?P<dst>.*)([ ]{32}(?P<notes>.+))?$')
    countries = {}
    pdf = PdfReader(io.BytesIO(pdf_data))
    pagenum = 0
    last_entry = None
    for page in pdf.pages:
        pagenum += 1
        countries[pagenum] = []
        logger.info(f"Starting to analyze page {pagenum}...")
        text = page.extract_text(extraction_mode="layout", layout_mode_space_vertically=False)
        if text and "Country/geographical area" in text and "Country" in text and "International" in text and "National" in text and "National (Significant)" in text and "UTC/DST" in text and "Note" in text:
            for line in text.split("\n"):
                #this is faster than having a "{128,} in the compiled country_regex
                match = country_regex.match(re.sub("[ ]{128,}", " "*32, line))
                if match == None:
                    # check if this is just a linebreak in the country name and append the value to the previous country
                    if re.sub("[ ]{128,}", " "*32, line) == line.strip() and last_entry != None and "Annex to ITU" not in line:
                        logger.debug(f"Adding to last country name: {line=}")
                        countries[pagenum][last_entry].name += f" {line.strip()}"
                    else:
                        last_entry = None           # don't append line continuations of non-real countries to a real country
                else:
                    match = match.groupdict() | {"dst": None, "notes": None}
                    if match["end"] and match["end"].strip() != "":
                        end_splitting = match["end"].split(" "*32)
                        if len(end_splitting) >= 1:
                            match["dst"] = end_splitting[0]
                        if len(end_splitting) >= 2:
                            match["notes"] = end_splitting[1]
                    match = {key: (value.strip() if value != None else None) for key, value in match.items()}
                    # logger.debug("****************")
                    # logger.debug(f"{match['country'] = }")
                    # logger.debug(f"{match['code'] = }")
                    # logger.debug(f"{match['international_prefix'] = }")
                    # logger.debug(f"{match['national_prefix'] = }")
                    # logger.debug(f"{match['format'] = }")
                    # logger.debug(f"{match['dst'] = }")
                    # logger.debug(f"{match['notes'] = }")
                    
                    if match["dst"] == None:        # all real countries have a dst entry
                        last_entry = None           # don't append line continuations of non-real countries to a real country
                    else:
                        country_code = f"+{match['code']}"
                        pattern = subpattern_matchers(match['format'], True)
                        superpattern = matcher(pattern, r"(\([0-9/]+\))[ ]*\+[ ]*(.+)[ ]+digits", match['format'], lambda result: result)
                        if pattern == None and superpattern != None:
                            #logger.debug(f"Trying superpattern: '{match['format']}' --> '{superpattern.group(1)}' ## '{superpattern.group(2)}'")
                            subpattern = subpattern_matchers(superpattern.group(2), False)
                            if subpattern != None:
                                pattern = re.sub("/", "|", superpattern.group(1)) + subpattern
                        if pattern == None:
                            logger.warning(f"Unknown format description for {match['country']} ({country_code}): '{match['format']}'")
                            pattern = "[0-9]*"                    
                        country = Quicksy_Country(match['country'], country_code, f"^{pattern}$")
                        countries[pagenum].append(country)
                        last_entry = len(countries[pagenum]) - 1
                        logger.info(f"Page {pagenum}: Found {len(countries[pagenum])} countries so far...")
    
    return [c for cs in countries.values() for c in cs]

def matcher(previous_result, regex, text, closure):
    if previous_result != None:
        return previous_result
    matches = re.match(regex, text)
    if matches == None:
        return None
    else:
        return closure(matches)

def subpattern_matchers(text, should_end_with_unit):
    if should_end_with_unit:
        if text[-6:] != "digits":
            logger.error(f"should_end_with_unit set but not ending in 'digits': {text[-6:] = }")
            return None
        text = text[:-6]
    
    def subdef(result):
        retval = f"[0-9]{{"
        grp1 = result.group(1) if result.group(1) != "up" else "1"
        retval += f"{grp1}"
        if result.group(3) != None:
            retval += f",{result.group(3)}"
        retval += f"}}"
        return retval
    pattern = []
    parts = [x.strip() for x in text.split(",")]
    for part in parts:
        result = matcher(None, r"(up|[0-9]+)([ ]*to[ ]*([0-9]+)[ ]*)?", part, subdef)
        #logger.debug(f"{part=} --> {result=}")
        if result != None:
            pattern.append(result)
    if len(pattern) == 0:
        return None
    return "(" + "|".join(pattern) + ")"

logger.info("Downloading PDF...")
response = requests.get("https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-E.164C-2011-PDF-E.pdf")
logger.info("Parsing PDF...")
countries = parse_pdf(response.content)
print("""// This file was automatically generated by scripts/itu_pdf_to_swift.py
// Please run this python script again to update this file
// Example ../scripts/itu_pdf_to_swift.py > Classes/CountryCodes.swift

public struct Quicksy_Country: Identifiable, Hashable {
    public let id = UUID()
    public let name: String
    public let code: String
    public let pattern: String
}
""")
print(f"public let COUNTRY_CODES: [Quicksy_Country] = [")
for country in countries:
    print(f"    {country}")
print(f"]")
