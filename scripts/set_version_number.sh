#!/bin/sh

# Abort on Error
set -e
set -x

cd Monal

echo ""
echo "***************************************************"
echo "* Setting buildNumber to $buildNumber and version to $version *"
echo "***************************************************"

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildNumber" "NotificationService/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildNumber" "shareSheet-iOS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildNumber" "$APP_NAME-Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "NotificationService/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "shareSheet-iOS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$APP_NAME-Info.plist"
