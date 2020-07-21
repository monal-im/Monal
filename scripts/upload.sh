#!/bin/sh

ls -l build/ipa/$APP_NAME.ipa
#ls -l build/app/$APP_NAME.tar
#curl -X POST -F "ios=@build/ipa/$APP_NAME.ipa" -F "mac=@build/app/$APP_NAME.tar" -F "changes=@../changes.txt" -H "X-Secret: $KEY_PASSWORD" https://www.eightysoft.de/monal/upload.php

curl -X POST -F "ios=@build/ipa/$APP_NAME.ipa" -F "changes=@../changes.txt" -H "X-Secret: $KEY_PASSWORD" https://www.eightysoft.de/monal/upload.php
