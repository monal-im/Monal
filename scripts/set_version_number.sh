#!/bin/sh

# Abort on Error
set -e

cd Monal

echo ""
echo "***************************************************"
echo "* Setting buildNumber to $buildNumber and version to $buildVersion *"
echo "***************************************************"
sleep 1

set -x

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildNumber" "NotificationService/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildNumber" "shareSheet-iOS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildNumber" "$APP_NAME-Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $buildVersion" "NotificationService/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $buildVersion" "shareSheet-iOS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $buildVersion" "$APP_NAME-Info.plist"
