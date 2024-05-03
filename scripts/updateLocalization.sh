#/bin/bash

set -e

cd "$(dirname "$0")"
cd ../Monal

if ! which bartycrouch > /dev/null; then
    echo "ERROR: BartyCrouch not installed, download it from https://github.com/Flinesoft/BartyCrouch"
    exit 1
fi

compile_swift="NO"
if [ "x$2" != "x" ]; then
    compile_swift="$2"
fi

function pullCurrentState {
    #subshell to not leak from "cd $folder"
    (
        cd "localization/external"
        if [[ $1 == "BUILDSERVER" ]]; then
            git remote set-url origin git@main.translation.repo:monal-im/Monal-localization-main.git
        else
            git remote set-url origin git@github.com:monal-im/Monal-localization-main.git
        fi
        echo "Git remote is now:"
        git remote --verbose
        git checkout main
        git reset --hard origin/main
    )
    #subshell to not leak from "cd $folder"
    (
        cd "shareSheet-iOS/localization/external"
        if [[ $1 == "BUILDSERVER" ]]; then
            git remote set-url origin git@sharesheet.translation.repo:monal-im/Monal-localization-shareSheet.git
        else
            git remote set-url origin git@github.com:monal-im/Monal-localization-shareSheet.git
        fi
        echo "Git remote is now:"
        git remote --verbose
        git checkout main
        git reset --hard origin/main
    )
}

function runBartycrouch {
    # https://github.com/Flinesoft/BartyCrouch#exclude-specific-views--nslocalizedstrings-from-localization
    # update normally using bartycrouch and use it to sync our SwiftUI translations from base language to all other languages
    bartycrouch update -x
    # clean up all files
    for folder in "localization/external" "shareSheet-iOS/localization/external"; do
        for file in $folder/*.lproj/*.strings; do
            # Remove empty lines
            sed -i '' '/^$/d' $file
            # Remove default comments that are not supported by weblate
            sed -i '' '/^\/\* No comment provided by engineer\. \*\/$/d' $file
            # Fix empty RHS
            sed -E -i '' 's|^(.*) = "";$|\1 = \1;|' $file
        done
    done
    # lint everything now
    bartycrouch lint -x -w
}

echo ""
echo "***************************************"
echo "*     Initializing submodules         *"
echo "***************************************"
git submodule deinit --all -f
git submodule update --init --recursive --remote
pullCurrentState "$@"

if [ "$compile_swift" == "YES" ]; then
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
fi

echo ""
echo "***************************************"
echo "*     Removing unused strings         *"
echo "***************************************"
# update strings to remove everything that's now unused (that includes swiftui strings we'll readd below)
cp .bartycrouch.toml .bartycrouch.toml.orig
sed 's/additive = true/additive = false/g' .bartycrouch.toml > .bartycrouch.toml.new
rm .bartycrouch.toml
mv .bartycrouch.toml.new .bartycrouch.toml
runBartycrouch
rm .bartycrouch.toml
mv .bartycrouch.toml.orig .bartycrouch.toml
# now restore original state for all languages but our base one (otherwise every swiftui translation will be deleted)
mv "localization/external/Base.lproj/Localizable.strings" "localization/external/Base.lproj/Localizable.strings.updated"
pullCurrentState "$@"
mv "localization/external/Base.lproj/Localizable.strings.updated" "localization/external/Base.lproj/Localizable.strings"

echo ""
echo "***************************************"
echo "*     Extracting xliff files          *"
echo "***************************************"
if [ -e localization.tmp ]; then
    rm -rf localization.tmp
fi
# extract xliff file (has to be run multiple times, even if no error occured, don't ask me why)
# we use grep here to test for a dummy string to detect if our run succeeded
dummy="DON'T TRANSLATE: $(head /dev/urandom | LC_ALL=C tr -dc A-Za-z0-9 | head -c 8)"
#echo "\nlet swiftuiTranslationRandomDummyString = Text(\"$dummy\")" >> Classes/SwiftuiHelpers.swift
x=$((1))
while [[ $x -lt 16 ]]; do
    echo "STARTING RUN $x..."
    while ! xcrun xcodebuild -workspace "Monal.xcworkspace" -scheme "Monal" -sdk iphoneos -configuration "Beta" -allowProvisioningUpdates -exportLocalizations -localizationPath localization.tmp -exportLanguage base SWIFT_EMIT_LOC_STRINGS="$compile_swift"; do
        echo "ERROR, TRYING AGAIN..."
    done
    echo "RUN $x SUCCEEDED, EXTRACTING STRINGS FROM XLIFF!"
    # extract additional strings from xliff file and add them to our strings file (bartycrouch will remove duplicates later on)
    ../scripts/xliff_extractor.py -x "localization.tmp/base.xcloc/Localized Contents/base.xliff"
    x=$((x+1))
done
if ! grep -q "$dummy" "localization/external/Base.lproj/Localizable.strings"; then
    echo "Could not extract dummy string after $x runs!"
    #exit 1
fi
awk "!/$dummy/" "localization/external/Base.lproj/Localizable.strings" > "localization/external/Base.lproj/Localizable.strings.new"
mv "localization/external/Base.lproj/Localizable.strings.new" "localization/external/Base.lproj/Localizable.strings"
rm -rf *A\ Document\ Being\ Saved\ By\ xcodebuild*

echo ""
echo "*********************************************************"
echo "*     Using batrycrouch to update all languages         *"
echo "*********************************************************"
runBartycrouch
if [ -e localization.tmp ]; then
    rm -rf localization.tmp
fi

echo ""
echo "*******************************************"
echo "*     Showing results as git diff         *"
echo "*******************************************"
for folder in "localization/external" "shareSheet-iOS/localization/external"; do
    #subshell to not leak from "cd $folder"
    (
        cd $folder
        echo "Diff of $folder:"
        git diff || true
        if [[ $1 != "NOCOMMIT" ]]; then
            git add -u
            # empty commits should not abort this script
            git commit -m "Updated translations via BartyCrouch xliff extractor" || true
            git log -n 2
            git remote --verbose
            git push
        fi
    )
done

echo ""
echo "***************************************"
echo "*     Cleaning up submodules          *"
echo "***************************************"
git submodule deinit --all -f
git submodule update --init --recursive

exit 0
