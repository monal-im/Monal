#!/usr/bin/env python3
import sys
import json
import hashlib
import argparse
import logging
from pathlib import Path
import re

SEMVER_RE = re.compile(r'^(\d+)\.(\d+)\.(\d+)')

def sha256_of(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()

def extract_semver_tuple(version: str):
    """
    Extracts MAJOR.MINOR.PATCH from a version string.
    Ignores suffixes like -beta, +build, etc.
    Returns tuple (major, minor, patch) as ints.
    """
    m = SEMVER_RE.match(version)
    if not m:
        return (0, 0, 0)
    return tuple(int(x) for x in m.groups())

logging.basicConfig(level=logging.DEBUG, stream=sys.stderr, format="%(asctime)s [%(levelname)-7s] %(module)s: %(message)s")
logger = logging.getLogger("__main__")

parser = argparse.ArgumentParser(description="Read lines from stdin and merge SHA256 → line mappings into a JSON structure under a given version.")
parser.add_argument("--version", required=True, help="Version string to use as the top-level JSON key")
parser.add_argument("--base-json", required=True, help="Path to existing JSON file to augment")
args = parser.parse_args()

# Load base JSON or start fresh
if args.base_json:
    base_path = Path(args.base_json)
    if not base_path.exists():
        logger.error(f"Base JSON file not found: {args.base_json}")
        sys.exit(1)
    with base_path.open("r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            logger.exception(f"Malformed JSON in base file: {e}")
            sys.exit(1)
else:
    data = {}

# Ensure the version key exists
version = ".".join(map(str, extract_semver_tuple(args.version)))
if version not in data:
    data[version] = {}

# Merge stdin-derived entries, without overwriting existing keys
for line in sys.stdin:
    clean = line.rstrip("\n")
    digest = sha256_of(clean)
    if digest not in data[version]:
        data[version][digest] = clean

# Extract all semantic version tuples and keep only the newest versions (ignoring suffixes like "-b1", "+1.2.3" etc.)
version_tuples = {}
for v in data.keys():
    version_tuples[v] = extract_semver_tuple(v)
newest_tuple = max(version_tuples.values())
newest_versions = {v for v, t in version_tuples.items() if t == newest_tuple}
for v in list(data.keys()):
    if v not in newest_versions:
        del data[v]

# Output the augmented JSON
with base_path.open("w", encoding="utf-8") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
