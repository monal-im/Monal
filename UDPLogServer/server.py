#!/usr/bin/env python3
import sys
import argparse
import socket
import ipaddress
import json
import zlib
import hashlib
from Cryptodome.Cipher import AES

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

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

# parse commandline
parser = argparse.ArgumentParser(formatter_class=argparse.RawTextHelpFormatter, description="Monal UDP-Logserver.", epilog="WARNING: WE DO NOT ENHANCE ENTROPY!! PLEASE MAKE SURE TO USE A ENCRYPTION KEY WITH PROPER ENTROPY!!")
parser.add_argument("-k", "--key", type=str, required=True, metavar='KEY', help="AES-Key to use for decription of incoming data")
parser.add_argument("-l", "--listen", type=str, metavar='HOSTNAME', help="Local hostname or IP to listen on (Default: :: e.g. any)", default="::")
parser.add_argument("-p", "--port", type=int, metavar='PORT', help="Port to listen on (Default: 5555)", default=5555)
args = parser.parse_args()

# "derive" 256 bit key
m = hashlib.sha256()
m.update(bytes(args.key, "UTF-8"))
key = m.digest()

# create listening udp socket and process all incoming packets
sock = socket.socket(socket.AF_INET6 if ipaddress.ip_address(args.listen).version==6 else socket.AF_INET, socket.SOCK_DGRAM)
sock.bind((args.listen, args.port))
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
    
    # decode raw json encoded data
    decoded = json.loads(str(payload, "UTF-8"))
    
    # print original formatted log message
    print(decoded["formattedMessage"], end="", flush=True)
