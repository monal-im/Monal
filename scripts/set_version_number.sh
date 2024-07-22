#!/bin/sh

# Abort on Error
set -e

cd Monal

echo ""
echo "*******************************************"
echo "*     Setting buildNumber to $buildNumber *"
echo "*******************************************"

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildNumber" "NotificationService/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildNumber" "shareSheet-iOS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildNumber" "$APP_NAME-Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$APP_NAME-Info.plist"