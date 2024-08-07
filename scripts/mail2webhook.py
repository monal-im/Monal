#!/usr/bin/env python3
import sys
import argparse
import email
import email.parser
import re
import requests

# see https://stackoverflow.com/a/60978847/3528174
def to_camel_case(text):
    s = text.replace("-", " ").replace("_", " ")
    s = s.split()
    if len(text) == 0:
        return text
    return s[0].lower() + ''.join(i.capitalize() for i in s[1:])

# parse commandline
parser = argparse.ArgumentParser(formatter_class=argparse.RawTextHelpFormatter, description="Simple python script to trigger a github ")
parser.add_argument("--token", metavar='TOKEN', required=True, help="Github token to use to authenticate the workflow trigger workflow")
parser.add_argument("--repo", metavar='REPO', required=True, help="Github user/organisation and repository name to trigger the workflow in (Example: 'monal-im/Monal')")
parser.add_argument("--type", metavar='TYPE', required=True, help="Event type to trigger the github workflow with")
parser.add_argument("--filter", metavar='FILTER', default=[], action='append', required=False, help="'key=value-regex' pairs that should be used to filter the app properties given in the mail body")
args = parser.parse_args()


parser = email.parser.BytesParser()
message = parser.parse(sys.stdin.buffer)

subject = re.sub(r'\s+', ' ', message["subject"]).strip()
date = message["date"]

# python > 3.9 variant
#body = message.get_body(preferencelist=("plain",))

# python <= 3.9 variant
# see https://stackoverflow.com/a/32840516/3528174
body = ""
if message.is_multipart():
    for part in message.walk():
        ctype = part.get_content_type()
        cdispo = str(part.get('Content-Disposition'))
        if ctype == 'text/plain' and 'attachment' not in cdispo:
            body = part.get_payload(decode=True)  # decode
            break
else:
    body = message.get_payload(decode=True)

# transform body into an array of stripped strings
body = [s.strip() for s in str(body, 'UTF-8').split("\n")]

# parse app properties
properties = {to_camel_case(k.strip()): v.strip() for k, v in [line.split(": ", 1) for line in body if len(line.split(": ", 1)) > 1]}

# sanity checks and state extraction
match = re.match(r"^The status of your \((?P<platform>.+)\) app, (?P<app_name>.+), is now \"(?P<state>.+)\"$", subject)
if match == None:
    print(f"Mail subject does not contain proper state: '{subject}'", file=sys.stderr)
    sys.exit(0)
state = {"_"+to_camel_case(k.strip()): v.strip() for k, v in match.groupdict().items()}
state["_state"] = to_camel_case(state["_state"].strip())
if state["_appName"] != properties["appName"]:
    print(f"Mail subject states different app name than properties in mail body: stateAppName='{state['_appName']}', appName='{properties['appName']}'", file=sys.stderr)
    sys.exit(0)

# merge body properties and extracted state
properties = state | {"_datetime": date} | properties
#print(properties)

# filter everything using the given commandline arguments
for entry in args.filter:
    k, v = entry.split("=", 1)
    if k not in properties:
        print(f"Unknown filter key: '{k}'", file=sys.stderr)
        sys.exit(0)
    if re.search(v, properties[k]) == None:
        print(f"Wrong {k}: '{properties[k]}'", file=sys.stderr)
        sys.exit(0)

# trigger workflow
with requests.post(f"https://api.github.com/repos/{args.repo}/dispatches", json={
    "event_type": args.type,
    "client_payload": properties,
}, headers={
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
    "Authorization": f"Bearer {args.token}"
}) as r:
    r.raise_for_status()

sys.exit(0)
