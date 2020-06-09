#!/bin/bash

if [[ -e $1.key ]]; then
	echo "Keyfile $1.key already existing, choose another one or delete it first!"
	exit 1
fi
if [[ -z "$1" ]]; then
	echo "Usage: $(basename "$0") <cert filename without extension>"
	exit 2
fi

cd "$(dirname "$0")"
openssl genrsa -out $1.key 2048
openssl req -config config -new -key $1.key -out $1.csr

echo ""
echo ""
cat $1.csr
echo ""
echo "Upload $(pwd)/$1.csr to Apple and press enter once you downloaded the resulting certificate to $(pwd)/$1.cer"
read dummy
openssl x509 -in $1.cer -inform DER -out $1.pem -outform PEM
openssl pkcs12 -export -inkey $1.key -in $1.pem -out $1.p12 -passout pass:1234
echo "$1.p12 with password '1234' successfully created"
