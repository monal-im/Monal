#!/bin/bash

KEY_PASSWORD="$(cat password.txt)"
for file in *.mobileprovision *.provisionprofile adhoc.p12 dev-id.p12 adhoc.cer apple.cer dev-id.cer; do
	echo "Encrypting '$file' --> '$file.enc'"
	openssl aes-256-cbc -k "$KEY_PASSWORD" -in "$file" -out "$file.enc" -a -md sha256;
done
