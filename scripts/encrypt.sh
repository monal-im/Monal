#!/bin/bash

KEY_PASSWORD="$(cat password.txt)"
for file in *.mobileprovision *.provisionprofile *.p12 *.cer; do
	echo "Encrypting '$file' --> '$file.enc'"
	openssl aes-256-cbc -k "$KEY_PASSWORD" -in "$file" -out "$file.enc" -a -md sha256;
done
