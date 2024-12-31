#!/usr/bin/env python3
import sys
import argparse
import socket
import ipaddress
import json
import zlib
import hashlib
import struct
import pathlib

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

# import optional/alternative modules
try:
    from xtermcolor import colorize
except ImportError as e:
    eprint(e)
    def colorize(text, rgb=None, ansi=None, bg=None, ansi_bg=None, fd=1, **kwargs):
        print(text, **kwargs)
try:
    from Cryptodome.Cipher import AES  # pycryptodomex
except ImportError as e:
    from Crypto.Cipher import AES  # pycryptodome

def flag_to_kwargs(flag):
    kwargs = {}
    if flag != None:
        if flag & 1:     # error
            kwargs = {"ansi": 9, "ansi_bg": 0}
        elif flag & 2:   # warning
            kwargs = {"ansi": 208, "ansi_bg": 0}
        elif flag & 4:   # info
            kwargs = {"ansi": 40, "ansi_bg": None}
        elif flag & 8:   # debug
            kwargs = {"ansi": 39, "ansi_bg": None}
        elif flag & 16:  # verbose
            kwargs = {"ansi": 7, "ansi_bg": None}
        elif flag & 32:  # stderr
            kwargs = {"ansi": 9, "ansi_bg": None}
        elif flag & 64:  # stdout
            kwargs = {"ansi": 0, "ansi_bg": None}
        else:
            kwargs = {"ansi": 0, "ansi_bg": None}
    return kwargs

def decrypt(ciphertext, key):
    iv = ciphertext[:12]
    if len(iv) != 12:
        raise Exception("Cipher text is damaged: invalid iv length")

    tag = ciphertext[12:28]
    if len(tag) != 16:
        raise Exception("Cipher text is damaged: invalid tag length")

    encrypted = ciphertext[28:]

    # Construct AES cipher, with old iv.
    cipher = AES.new(key, AES.MODE_GCM, iv)

    # Decrypt and verify.
    try:
        plaintext = cipher.decrypt_and_verify(encrypted, tag)
    except ValueError as e:
        raise Exception("Cipher text is damaged: {}".format(e))
    return plaintext

def formatLogline(entry):
    LOGLEVELS = {v: k for k, v in {
        "ERROR": 1,
        "WARNING": 2,
        "INFO": 4,
        "DEBUG": 8,
        "VERBOSE": 16,
        "STDERR": 32,
        "STDOUT": 64,
        "STATUS": 256,
    }.items()}
    file = pathlib.PurePath(entry["file"])
    return "%s [%s] %s [%s (QOS:%s)] %s at %s:%lu: %s" % (
        entry["timestamp"],
        LOGLEVELS[entry["flag"]].rjust(6),
        entry["tag"]["processName"],
        "%s:%s" % (entry["threadID"], entry["tag"]["queueThreadLabel"]) if entry["threadID"] != entry["tag"]["queueThreadLabel"] else entry["threadID"],
        entry["tag"]["qosName"],
        entry["function"],
        "%s/%s" % (file.parent.name, file.name),
        entry["line"],
        entry["message"],
    )

# parse commandline
parser = argparse.ArgumentParser(formatter_class=argparse.RawTextHelpFormatter, description="Monal UDP-Logserver.", epilog="WARNING: WE DO NOT ENHANCE ENTROPY!! PLEASE MAKE SURE TO USE A ENCRYPTION KEY WITH PROPER ENTROPY!!")
parser.add_argument("-k", "--key", type=str, required=True, metavar='KEY', help="AES-Key to use for decription of incoming data")
parser.add_argument("-l", "--listen", type=str, metavar='HOSTNAME', help="Local hostname or IP to listen on (Default: :: e.g. any)", default="::")
parser.add_argument("-p", "--port", type=int, metavar='PORT', help="Port to listen on (Default: 5555)", default=5555)
parser.add_argument("-f", "--file", type=str, required=False, metavar='FILE', help="Filename to write the log to (in addition to stdout)")
parser.add_argument("-r", "--rawfile", type=str, required=False, metavar='RAW', help="Filename to write the RAW log to")
args = parser.parse_args()

# "derive" 256 bit key
m = hashlib.sha256()
m.update(bytes(args.key, "UTF-8"))
key = m.digest()

# create listening udp socket and process all incoming packets
sock = socket.socket(socket.AF_INET6 if ipaddress.ip_address(args.listen).version==6 else socket.AF_INET, socket.SOCK_DGRAM)
sock.bind((args.listen, args.port))
last_counter = None
last_processID = None
logfd = None
rawfd = None
receiveCounter = 0
if args.file:
    print(colorize("Opening logfile '%s' for writing..." % args.file, ansi=15, ansi_bg=0), flush=True)
    logfd = open(args.file, "w")
if args.rawfile:
    print(colorize("Opening RAW logfile '%s' for writing..." % args.rawfile, ansi=15, ansi_bg=0), flush=True)
    rawfd = open(args.rawfile, "wb")
while True:
    # receive raw udp packet
    payload, client_address = sock.recvfrom(65536)
    
    # decrypt raw data
    try:
        payload = decrypt(payload, key)
    except Exception as e:
        eprint(e)
        continue        # process next udp packet
    
    # decompress raw data
    payload = zlib.decompress(payload, zlib.MAX_WBITS | 16)
    
    # log to RAW file
    if rawfd:
        size = struct.pack("!L", len(payload))
        rawfd.write(size+payload)
    
    # decode raw json encoded data
    decoded = json.loads(str(payload, "UTF-8"))
    
    # increment local receive counter and add it to data
    receiveCounter += 1
    decoded["_receiveCounter"] = receiveCounter
    
    # check if counter jumped over some lines
    logline = ""
    if last_processID != None and decoded["tag"]["processID"] != last_processID:
        logline += "PROCESS SWITCH FROM %s TO %s" % (last_processID, decoded["tag"]["processID"])
    if last_counter != None and decoded["tag"]["counter"] != last_counter + 1:
        if len(logline) != 0:
            logline += ": "
        logline += "counter jumped from %d to %d leaving out %d lines" % (last_counter, decoded["tag"]["counter"], decoded["tag"]["counter"] - last_counter - 1)
    if len(logline) != 0:
        if logfd:
            print(logline, file=logfd)
        print(colorize(logline, ansi=15, ansi_bg=0), flush=True)
    
    # deduce log color from loglevel
    kwargs = flag_to_kwargs(decoded["flag"] if "flag" in decoded else None)
    
    # print original formatted log message
    logline = "%s%d: %s" % (
        "+++ LOG_QUEUE_DISABLED +++ " if "tag" in decoded and "loggingQueueSuspended" in decoded["tag"] and decoded["tag"]["loggingQueueSuspended"]==True else "",
        decoded["tag"]["counter"],
        formatLogline(decoded)
    )
    if logfd:
        print(logline, file=logfd)
    print(colorize(logline, **kwargs), flush=True)
    
    # update state
    last_processID = decoded["tag"]["processID"]
    last_counter = decoded["tag"]["counter"]
