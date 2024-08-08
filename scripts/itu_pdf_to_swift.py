#!/usr/bin/env python3
import requests
import io
from pypdf import PdfReader
import re
import logging

logging.basicConfig(level=logging.DEBUG, format="%(asctime)s [%(levelname)-7s] %(name)s {%(threadName)s} %(filename)s:%(lineno)d: %(message)s")
logger = logging.getLogger(__name__)

class Quicksy_Country:
    def __init__(self, alpha2mapping, name, alpha2, code, pattern):
        self.alpha2mapping = alpha2mapping
        self.name = name
        self.alpha2 = alpha2
        self.code = code
        self.pattern = pattern
    
    def __repr__(self):
        # map ITU country names to wikidata names
        itu2wikidata = {
            "Ireland": "Republic of Ireland",
            "China": "People's Republic of China",
            "Taiwan, China": "Taiwan",
            "Hong Kong, China": "Hong Kong",
            "Gambia": "The Gambia",
            "Falkland Islands (Malvinas)": "Falkland Islands",
            "Dominican Rep.": "Dominican Republic",
            "Dem. Rep. of the Congo": "Democratic Republic of the Congo",
            "Congo": "Republic of the Congo",
            "Czech Rep.": "Czech Republic",
            "Dem. People's Rep. of Korea": "North Korea",
            "Central African Rep.": "Central African Republic",
            "Bolivia (Plurinational State of)": "Bolivia",
            "Bahamas": "The Bahamas",
            "Korea (Rep. of)": "South Korea",
            "Iran (Islamic Republic of)": "Iran",
            "Lao P.D.R.": "Laos",
            "Moldova (Republic of)": "Moldova",
            "Micronesia": "Federated States of Micronesia",
            "Netherlands": "Kingdom of the Netherlands",
            "Russian Federation": "Russia",
            "Syrian Arab Republic": "Syria",
            "The Former Yugoslav Republic of Macedonia": "North Macedonia",
            "United States": "United States of America",
            "Vatican": "Vatican City",
            "Venezuela (Bolivarian Republic of)": "Venezuela",
            "Viet Nam": "Vietnam",
            "Swaziland": "Eswatini",
            "Sint Maarten (Dutch part)": "Sint Maarten",
            "Brunei Darussalam": "Brunei",
            "Bonaire, Sint Eustatius and Saba": "Caribbean Netherlands",
            "Côte d'Ivoire": "Ivory Coast",
            "Sao Tome and Principe": "São Tomé and Príncipe",
            "Timor-Leste": "East Timor",
            "Northern Marianas": "Northern Mariana Islands",
        }
        country = self.name
        if country in itu2wikidata:
            country = itu2wikidata[country]
        
        # map ITU country names to wikidata names and return swift code with alpha-2 country code instead of localizable name
        if country in alpha2mapping:
            return f"Quicksy_Country(name: nil, alpha2: \"{alpha2mapping[country]}\", code: \"{self.code}\", pattern: \"{self.pattern}\"),"
        # return swift code with localizable name for every country we don't know the alpha-2 code for
        return f"Quicksy_Country(name: NSLocalizedString(\"{self.name}\", comment:\"quicksy country\"), alpha2: nil, code: \"{self.code}\", pattern: \"{self.pattern}\"),"

def parse_pdf(pdf_data, alpha2mapping):
    logger.info("Parsing PDF...")
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
                            pattern = "[0-9]+"
                        country = Quicksy_Country(alpha2mapping, match['country'], None, country_code, f"^{pattern}$")
                        countries[pagenum].append(country)
                        last_entry = len(countries[pagenum]) - 1
                        logger.info(f"Page {pagenum}: Found {len(countries[pagenum])} countries so far...")
    
    logger.info(f"Parsing finished: Extracted {sum([len(cs) for cs in countries.values()])} countries...")
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

def get_sparql_results(query):
    import sys
    from SPARQLWrapper import SPARQLWrapper, JSON
    user_agent = "monal-im itu pdf parser/%s.%s" % (sys.version_info[0], sys.version_info[1])
    sparql = SPARQLWrapper("https://query.wikidata.org/sparql", agent=user_agent)
    sparql.setQuery(query)
    sparql.setReturnFormat(JSON)
    return sparql.query().convert()


logger.info("Downloading Wikidata country names to ISO 3166-1 alpha-2 codes mapping...")
results = get_sparql_results("""SELECT ?country ?countryLabel ?code WHERE {
	?country wdt:P297 ?code .
	SERVICE wikibase:label { bd:serviceParam wikibase:language "en" }
}""")
alpha2mapping = {result["countryLabel"]["value"]: result["code"]["value"] for result in results["results"]["bindings"]}

logger.info("Downloading PDF...")
response = requests.get("https://www.itu.int/dms_pub/itu-t/opb/sp/T-SP-E.164C-2011-PDF-E.pdf")
countries = parse_pdf(response.content, alpha2mapping)

# output complete swift code
print("""// This file was automatically generated by scripts/itu_pdf_to_swift.py
// Please run this python script again to update this file
// Example ../scripts/itu_pdf_to_swift.py > Classes/CountryCodes.swift

public struct Quicksy_Country: Identifiable, Hashable {
    public let id = UUID()
    public let name: String?        //has to be optional because we don't want to have NSLocalizedString() if we know the alpha-2 code
    public let alpha2: String?      //has to be optional because the alpha-2 mapping can fail
    public let code: String
    public let pattern: String
}
""")
print(f"public let COUNTRY_CODES: [Quicksy_Country] = [")
for country in countries:
    print(f"    {country}")
print(f"]")
