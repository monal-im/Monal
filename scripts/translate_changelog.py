#!/usr/bin/env python3
import sys
import json
import hashlib
import argparse
import logging
from pathlib import Path

def sha256_of(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()

logging.basicConfig(level=logging.DEBUG, stream=sys.stderr, format="%(asctime)s [%(levelname)-7s] %(module)s: %(message)s")
logger = logging.getLogger("__main__")

parser = argparse.ArgumentParser(description="Lookup SHA256 of input lines in a JSON file and print matching value or original line.")
parser.add_argument("--json-file", required=True, help="Path to the JSON file to search")
args = parser.parse_args()

json_path = Path(args.json_file)
if not json_path.exists():
    logger.error(f"JSON file not found: {args.json_file}")
    sys.exit(1)

try:
    with json_path.open("r", encoding="utf-8") as f:
        data = json.load(f)
except json.JSONDecodeError as e:
    logger.exception(f"Malformed JSON in file: {e}")
    sys.exit(1)

# Read lines from stdin
for line in sys.stdin:
    clean = line.rstrip("\n")
    digest = sha256_of(clean)
    found = False

    # Search through all versions
    for version_dict in data.values():
        if digest in version_dict:
            print(version_dict[digest])
            found = True
            break

    if not found:
        print(clean)
