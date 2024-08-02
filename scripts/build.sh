#!/bin/bash

function exportMacOS {
    local EXPORT_OPTIONS_CATALYST="$1"
    local BUILD_TYPE="$2"

    xcodebuild -exportArchive \
        -archivePath "build/macos_$APP_NAME.xcarchive" \
        -exportPath "build/app" \
        -exportOptionsPlist "$EXPORT_OPTIONS_CATALYST" \
        -allowProvisioningUpdates \
        -configuration $BUILD_TYPE

    echo "build dir:"
    ls -l "build"
}

# Abort on Error
set -e

cd Monal

security unlock-keychain -p $(cat /Users/ci/keychain.txt) login.keychain
security set-keychain-settings -t 3600 -l ~/Library/Keychains/login.keychain

echo ""
echo "*******************************************"
echo "*     Update localizations submodules     *"
echo "*******************************************"
git submodule update -f --init --remote

echo ""
echo "*******************************************"
echo "*     Building rust packages & bridge     *"
echo "*******************************************"

bash ../rust/build-rust.sh

echo ""
echo "***************************************"
echo "*     Installing macOS & iOS Pods     *"
echo "***************************************"
pod install --repo-update

if [ "$BUILD_SCHEME" != "Quicksy" ]; then
    echo ""
    echo "***************************"
    echo "*     Archiving macOS     *"
    echo "***************************"
    xcrun xcodebuild \
        -workspace "Monal.xcworkspace" \
        -scheme "$BUILD_SCHEME" \
        -sdk macosx \
        -configuration $BUILD_TYPE \
        -destination 'generic/platform=macOS,variant=Mac Catalyst,name=Any Mac' \
        -archivePath "build/macos_$APP_NAME.xcarchive" \
        -allowProvisioningUpdates \
        archive \
        BUILD_LIBRARIES_FOR_DISTRIBUTION=YES \
        SUPPORTS_MACCATALYST=YES

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
        exportMacOS "$EXPORT_OPTIONS_CATALYST_APPSTORE" "$BUILD_TYPE"
    fi

    if [ ! -z ${EXPORT_OPTIONS_CATALYST_APP_EXPORT} ]; then
        echo "***********************************"
        echo "*    Exporting app macOS          *"
        echo "***********************************"
        exportMacOS "$EXPORT_OPTIONS_CATALYST_APP_EXPORT" "$BUILD_TYPE"

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
fi

echo ""
echo "*************************"
echo "*     Archiving iOS     *"
echo "*************************"
xcrun xcodebuild \
    -workspace "Monal.xcworkspace" \
    -scheme "$BUILD_SCHEME" \
    -sdk iphoneos \
    -configuration $BUILD_TYPE \
    -archivePath "build/ios_$APP_NAME.xcarchive" \
    -allowProvisioningUpdates \
    archive

echo ""
echo "*************************"
echo "*     Exporting iOS     *"
echo "*************************"
# see: https://gist.github.com/cocoaNib/502900f24846eb17bb29
# and: https://forums.developer.apple.com/thread/100065
xcodebuild \
    -exportArchive \
    -archivePath "build/ios_$APP_NAME.xcarchive" \
    -exportPath "build/ipa" \
    -exportOptionsPlist $EXPORT_OPTIONS_IOS \
    -configuration $BUILD_TYPE \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration

echo "build dir:"
find build
