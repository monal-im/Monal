#!/bin/sh

function buildAndExportMacOS {
    local APP_DEVELOPER_NAME="$1"
    local EXPORT_OPTIONS_CATALYST="$2"
    local BUILD_TYPE="$3"

    echo ""
    echo "***************************"
    echo "*     Archiving macOS     *"
    echo "***************************"
    xcrun xcodebuild -workspace "Monal.xcworkspace" -scheme "Monal" -sdk macosx -configuration $BUILD_TYPE -destination 'generic/platform=macOS,variant=Mac Catalyst,name=Any Mac' -archivePath "build/macos_$APP_NAME.xcarchive" clean archive CODE_SIGN_IDENTITY="$APP_DEVELOPER_NAME" CODE_SIGN_STYLE="Manual" SWIFT_ACTIVE_COMPILATION_CONDITIONS="$SWIFT_ACTIVE_COMPILATION_CONDITIONS" GCC_PREPROCESSOR_DEFINITIONS="$GCC_PREPROCESSOR_DEFINITIONS" BUILD_LIBRARIES_FOR_DISTRIBUTION=YES SUPPORTS_MACCATALYST=YES

    xcodebuild -exportArchive -archivePath "build/macos_$APP_NAME.xcarchive" -exportPath "build/app" -exportOptionsPlist "$EXPORT_OPTIONS_CATALYST" CODE_SIGN_STYLE="Manual"
    echo "build dir:"
    ls -l "build"
}

# Abort on Error
set -e

cd Monal

echo "Unlocking keychain..."
security default-keychain -s ios-build.keychain
# Unlock the keychain
security unlock-keychain -p travis ios-build.keychain
# Set keychain timeout to 1 hour for long builds
security set-keychain-settings -t 3600 -l ~/Library/Keychains/ios-build.keychain

ls -l ~/Library/MobileDevice/Provisioning\ Profiles/

# update SWIFT_ACTIVE_COMPILATION_CONDITIONS from GCC_PREPROCESSOR_DEFINITIONS
SWIFT_ACTIVE_COMPILATION_CONDITIONS=""
for entry in $GCC_PREPROCESSOR_DEFINITIONS; do
    SWIFT_ACTIVE_COMPILATION_CONDITIONS="$SWIFT_ACTIVE_COMPILATION_CONDITIONS $(echo "$entry" | awk -F= '{print $1}')"
done
export SWIFT_ACTIVE_COMPILATION_CONDITIONS

echo ""
echo "*******************************************"
echo "*     Update localizations submodules     *"
echo "*******************************************"
git submodule update --remote --init --merge

echo ""
echo "***************************************"
echo "*     Installing macOS & iOS Pods     *"
echo "***************************************"
pod install --repo-update

echo ""
echo "****************************"
echo "*     Exporting macOS      *"
echo "****************************"
# see: https://gist.github.com/cocoaNib/502900f24846eb17bb29
# and: https://forums.developer.apple.com/thread/100065
# and: for developer-id distribution (distribution *outside* of appstore) an developer-id certificate must be used for building
if [ ! -z ${EXPORT_OPTIONS_CATALYST_APPSTORE} ]; then
    echo "***************************************"
    echo "*    Exporting AppStore macOS         *"
    echo "***************************************"
    buildAndExportMacOS "$APP_DEVELOPER_NAME_APPSTORE" "$EXPORT_OPTIONS_CATALYST_APPSTORE" "AppStore"
fi

if [ ! -z ${EXPORT_OPTIONS_CATALYST_APP_EXPORT} ]; then
    echo "***********************************"
    echo "*    Exporting app macOS          *"
    echo "***********************************"
    buildAndExportMacOS "$APP_DEVELOPER_NAME_APP_EXPORT" "$EXPORT_OPTIONS_CATALYST_APP_EXPORT" "$BUILD_TYPE"

    echo ""
    echo "**************************"
    echo "*     Packing macOS zip  *"
    echo "**************************"
    cd build/app
    mkdir tar_release
    mv "$APP_NAME.app" "tar_release/$APP_DIR"
    cd tar_release
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "../$APP_NAME".zip
    cd ../../..
    ls -l build/app
fi

echo ""
echo "*************************"
echo "*     Archiving iOS     *"
echo "*************************"
xcrun xcodebuild -workspace "Monal.xcworkspace" -scheme "Monal" -sdk iphoneos -configuration $BUILD_TYPE -archivePath "build/ios_$APP_NAME.xcarchive" clean archive CODE_SIGN_IDENTITY="$IOS_DEVELOPER_NAME" CODE_SIGN_STYLE="Manual" SWIFT_ACTIVE_COMPILATION_CONDITIONS="$SWIFT_ACTIVE_COMPILATION_CONDITIONS" GCC_PREPROCESSOR_DEFINITIONS="$GCC_PREPROCESSOR_DEFINITIONS"

echo ""
echo "*************************"
echo "*     Exporting iOS     *"
echo "*************************"
# see: https://gist.github.com/cocoaNib/502900f24846eb17bb29
# and: https://forums.developer.apple.com/thread/100065
xcodebuild -exportArchive -archivePath "build/ios_$APP_NAME.xcarchive" -exportPath "build/ipa" -exportOptionsPlist $EXPORT_OPTIONS_IOS
echo "build dir:"
ls -l "build"