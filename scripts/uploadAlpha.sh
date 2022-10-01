#!/bin/sh

function sftp_upload {
sftp ${1} <<EOF
    put build/ipa/${APP_NAME}.ipa /var/www/downloads.monal-im.org/monal-im/alpha/iOS/
    put build/app/${APP_NAME}.tar /var/www/downloads.monal-im.org/monal-im/alpha/macOS/
    put ../changes.txt /var/www/downloads.monal-im.org/monal-im/alpha/iOS/
    quit
EOF
}

cd Monal
touch ../changes.txt
ls -l build/ipa/$APP_NAME.ipa
ls -l build/app/$APP_NAME.tar

sftp_upload downloads.monal-im.org@s1.eu.prod.push.monal-im.org
sftp_upload downloads.monal-im.org@s2.eu.prod.push.monal-im.org

curl -X POST -F "ios=@build/ipa/$APP_NAME.ipa" -F "mac=@build/app/$APP_NAME.tar" -F "changes=@../changes.txt" -H "X-Secret: $ALPHA_UPLOAD_SECRET" https://www.eightysoft.de/monal/upload.php