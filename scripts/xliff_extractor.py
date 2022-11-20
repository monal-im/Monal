#!/usr/bin/env python3
import os
import sys
import argparse
import re
import logging
import xml.etree.ElementTree as ElementTree

ns = {"def": "urn:oasis:names:tc:xliff:document:1.2"}
regex = re.compile('^"(.*)" = "(.*)";$')

logging.basicConfig(level=logging.DEBUG, stream=sys.stderr, format="%(asctime)s [%(levelname)-7s] %(module)s: %(message)s")
logger = logging.getLogger("__main__")

parser = argparse.ArgumentParser(formatter_class=argparse.RawTextHelpFormatter, description="XLIFF to Strings file converter.")
parser.add_argument("-x", "--xliff", type=str, required=True, metavar='FILE', help="XLIFF file to read")
args = parser.parse_args()

preexisting = 0
duplicates = 0
added = 0
logger.info("Loading XLIFF file at '%s'...", args.xliff)
xliff = ElementTree.parse(args.xliff)
for file in xliff.findall("./def:file", ns):
    path = file.attrib["original"]
    if os.path.exists(path) and path[-8:] == ".strings":
        logger.info("Reading strings data for '%s'...", path)
        with open(path) as stringsFile:
            strings = {}
            for line in stringsFile:
                parts = regex.search(line.strip())
                if not parts and len(line.strip()) > 0:
                    logger.debug("Not parsable, must be comment: %s", line.strip())
                elif parts:
                    strings[parts.group(1)] = True
                    if parts.group(1) != parts.group(2):
                        logger.warning("Strings LHS and RHS don't match: '%s' != '%s'!", parts.group(1), parts.group(2))
        preexisting = len(strings)
        logger.info("Adding missing strings data to '%s'...", path)
        with open(path, mode="a+", encoding="utf-8") as output:
            for unit in file.findall("./def:body/def:trans-unit", ns):
                string = unit.attrib["id"].replace("\n", "\\n")
                if string not in strings:
                    comment = "No comment provided by engineer."
                    if len(unit.find("./def:note", ns).text):
                        comment = unit.find("./def:note", ns).text.replace("\n", "\\n")
                    logger.debug("Adding new string (%s): %s", comment, string)
                    output.write("/* %s */\n" % comment)
                    output.write("\"%s\" = \"%s\";\n\n" % (string, string))
                    added += 1
                else:
                    duplicates += 1
logger.info("Done, preexisting: %d, duplicates: %d, added: %d", preexisting, duplicates, added)
