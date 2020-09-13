#!/usr/bin/env python3

import socket
import json
import zlib

server_address = '0.0.0.0'
server_port = 5555

sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind((server_address, server_port))

def tryCompletion(trylist):
    for entry in trylist:
        try:
            return json.loads(entry)
        except json.decoder.JSONDecodeError:
            pass
    return None

while True:
    payload, client_address = sock.recvfrom(65536)
    payload = zlib.decompress(payload, wbits = zlib.MAX_WBITS | 16)
    #while len(payload):
        #decoded = tryCompletion([payload, payload + b"}", payload + b"\"}"])
        #if not decoded:
            #payload = payload[:-1]
        #else:
            #break
    decoded = json.loads(payload)
    print(decoded["formattedMessage"], end="", flush=True)
