#!/bin/sh

#decrypt all encrypted files
for file in ./scripts/*.enc; do
	echo "Decrypting '$file' --> '${file%%.enc}'..."
	openssl aes-256-cbc -k "$KEY_PASSWORD" -md sha256 -in "$file" -d -a -out "${file%%.enc}"
done

# Create a custom keychain
security create-keychain -p travis ios-build.keychain
# Make the custom keychain default, so xcodebuild will use it for signing
security default-keychain -s ios-build.keychain
# Unlock the keychain
security unlock-keychain -p travis ios-build.keychain
# Set keychain timeout to 1 hour for long builds
security set-keychain-settings -t 3600 -l ~/Library/Keychains/ios-build.keychain
# Add certificates to keychain and allow codesign to access them
echo "Importing 'apple.cer' into keychain..."
security import ./scripts/apple.cer -k ~/Library/Keychains/ios-build.keychain -T /usr/bin/codesign
for file in ./scripts/*.p12.enc; do
	cert="${file%%.p12.enc}"
	echo "Importing '$cert.p12' and '$cert.cer' into keychain..."
	security import $cert.cer -k ~/Library/Keychains/ios-build.keychain -T /usr/bin/codesign 
	security import $cert.p12 -k ~/Library/Keychains/ios-build.keychain -P 1234 -T /usr/bin/codesign
done
# Set Key partition list
security set-key-partition-list -S apple-tool:,apple: -s -k travis ios-build.keychain
security list-keychains -s ios-build.keychain

# Put the provisioning profile in place 
mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
cp ./scripts/*.mobileprovision ~/Library/MobileDevice/Provisioning\ Profiles/
cp ./scripts/*.provisionprofile ~/Library/MobileDevice/Provisioning\ Profiles/
