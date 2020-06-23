#!/bin/sh

ls -l build/ipa/$APP_NAME.ipa
curl -X POST -F "datei=@build/ipa/$APP_NAME.ipa" -F "changes=@../changes.txt" -H "X-Upload: ios" -H "X-Secret: $KEY_PASSWORD" https://www.eightysoft.de/monal/upload.php
ls -l build/app/$APP_NAME.tar
curl -X POST -F "datei=@build/app/$APP_NAME.tar" -F "changes=@../changes.txt" -H "X-Upload: macos" -H "X-Secret: $KEY_PASSWORD" https://www.eightysoft.de/monal/upload.php
