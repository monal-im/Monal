#!/bin/sh

# Abort on Error
set -e

cd Monal

echo ""
echo "*******************************************"
echo "*     Reading buildNumber                 *"
echo "*******************************************"
buildNumber=$(git tag --sort="v:refname" |grep "Build_iOS" | tail -n1 | sed 's/Build_iOS_//g')

echo ""
echo "*******************************************"
echo "*     Setting buildNumber to $buildNumber *"
echo "*******************************************"

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildNumber" "NotificaionService/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildNumber" "shareSheet-iOS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildNumber" "Monal-Info.plist"