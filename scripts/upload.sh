#!/bin/sh

ls -l build/ipa/$APP_NAME.ipa
if [ "$BUILD_MACOS" = true ] || grep -q "Friedrich" "$TRAVIS_BUILD_DIR/changes.txt"
then
	ls -l build/app/$APP_NAME.tar
	curl -X POST -F "ios=@build/ipa/$APP_NAME.ipa" -F "mac=@build/app/$APP_NAME.tar" -F "changes=@../changes.txt" -H "X-Secret: $KEY_PASSWORD" https://www.eightysoft.de/monal/upload.php
else
	curl -X POST -F "ios=@build/ipa/$APP_NAME.ipa" -F "changes=@../changes.txt" -H "X-Secret: $KEY_PASSWORD" https://www.eightysoft.de/monal/upload.php
fi