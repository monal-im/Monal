#!/bin/sh

#ls -l "build/ipa"
#cat build/ipa/DistributionSummary.plist
#cat build/ipa/ExportOptions.plist
ls -l build/ipa/$APP_NAME.ipa
curl -X POST -F "datei=@build/ipa/$APP_NAME.ipa" -F "changes=@../changes.txt" -H "X-Secret: $KEY_PASSWORD" https://www.eightysoft.de/monal/upload.php
