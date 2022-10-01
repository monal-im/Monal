#!/bin/sh

UPLOAD_TYPE=$1

function sftp_upload {
    buildNumber=$(git tag --sort="v:refname" |grep "Build_iOS" | tail -n1 | sed 's/Build_iOS_//g')
sftp ${1} <<EOF
    put build/app/Monal.zip /var/www/downloads.monal-im.org/monal-im/$UPLOAD_TYPE/macOS/Monal-${buildNumber}.zip
    quit
EOF
}

cd Monal

sftp_upload downloads.monal-im.org@s1.eu.prod.push.monal-im.org
sftp_upload downloads.monal-im.org@s2.eu.prod.push.monal-im.org