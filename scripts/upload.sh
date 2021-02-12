#!/bin/sh

cd Monal
touch ../changes.txt
ls -l build/ipa/$APP_NAME.ipa
ls -l build/app/$APP_NAME.tar
curl -X POST -F "ios=@build/ipa/$APP_NAME.ipa" -F "mac=@build/app/$APP_NAME.tar" -F "changes=@../changes.txt" -H "X-Secret: $ALPHA_UPLOAD_SECRET" https://www.eightysoft.de/monal/upload.php
