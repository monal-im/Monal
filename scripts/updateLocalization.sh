#/bin/bash

# commandline ./updateLocalization.sh BUILDSERVER|OTHER NOCOMMIT|COMMIT [YES|NO]
set -e

# Needed for xcbeautify
set -o pipefail

cd "$(dirname "$0")"
cd ../Monal

if ! which bartycrouch > /dev/null; then
    echo "ERROR: BartyCrouch not installed, download it from https://github.com/Flinesoft/BartyCrouch"
    exit 1
fi

compile_swift="YES"
if [[ $3 == "NO" ]]; then
    compile_swift="NO"
fi

# terminal escape sequences used
BOLD="\033[1m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m" # reset everything

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
    return 0
}

function runBartycrouch {
    # https://github.com/Flinesoft/BartyCrouch#exclude-specific-views--nslocalizedstrings-from-localization
    # update normally using bartycrouch and use it to sync our SwiftUI translations from base language to all other languages
    bartycrouch update -x
    retval=$?
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
    set +e
    bartycrouch lint -x -w
    set -e
    return $retval
}

function build_and_extract_xliff {
    scheme="$1"
    configuration="$2"
    rm -rf *A\ Document\ Being\ Saved\ By\ xcodebuild*
    if [ -e localization.tmp ]; then
        rm -rf localization.tmp
    fi
    NSUnbufferedIO=YES xcrun xcodebuild -workspace "Monal.xcworkspace" -scheme "$scheme" -sdk iphoneos -configuration "$configuration" -allowProvisioningUpdates clean  2>&1 | xcbeautify
    # if we compile the code, run at least one extraction without compiling, to catch strings wrapped in ifdefs etc.
    if [[ $compile_swift == "YES" ]]; then
        if ! NSUnbufferedIO=YES xcrun xcodebuild -workspace "Monal.xcworkspace" -scheme "$scheme" -sdk iphoneos -configuration "$configuration" -allowProvisioningUpdates -exportLocalizations -localizationPath ./localization.tmp -exportLanguage base SWIFT_EMIT_LOC_STRINGS="NO" 2>&1 | xcbeautify; then
            echo "*** BUILD FOR '$scheme' - '$configuration' WITH SWIFT_EMIT_LOC_STRINGS=NO RETURNED AN ERROR! ***"
            return 1
        fi
        echo "*** EXTRACTING STRINGS FROM XLIFF... ***"
        # extract additional strings from xliff file and add them to our strings file
        if ! ../scripts/xliff_extractor.py -x "localization.tmp/base.xcloc/Localized Contents/base.xliff"; then
            echo "*** XLIFF EXTRACTOR FAILED ***"
            return 2
        fi
    fi
    if ! NSUnbufferedIO=YES xcrun xcodebuild -workspace "Monal.xcworkspace" -scheme "$scheme" -sdk iphoneos -configuration "$configuration" -allowProvisioningUpdates -exportLocalizations -localizationPath ./localization.tmp -exportLanguage base SWIFT_EMIT_LOC_STRINGS="$compile_swift" 2>&1 | xcbeautify; then
        echo "*** BUILD FOR '$scheme' - '$configuration' RETURNED AN ERROR! ***"
        return 3
    fi
    echo "*** EXTRACTING STRINGS FROM XLIFF... ***"
    # extract additional strings from xliff file and add them to our strings file
    if ! ../scripts/xliff_extractor.py -x "localization.tmp/base.xcloc/Localized Contents/base.xliff"; then
        echo "*** XLIFF EXTRACTOR FAILED ***"
        return 4
    fi
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
echo "Update strings to remove everything that's now unused (that includes swiftui strings we'll readd below)..."
cp .bartycrouch.toml .bartycrouch.toml.orig
sed 's/additive = true/additive = false/g' .bartycrouch.toml.orig > .bartycrouch.toml
# bartycrouch will probably remove too much, but that doesn't matter because our build step and
# xliff extractor below will add everything back that's still present/needed
runBartycrouch
mv .bartycrouch.toml.orig .bartycrouch.toml
echo "Now restore original state for all languages but our base one (otherwise every swiftui translation will be deleted)..."
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
dummyname="$(head /dev/urandom | LC_ALL=C tr -dc A-Za-z | head -c 8)"
cp Classes/SwiftuiHelpers.swift Classes/SwiftuiHelpers.swift.orig
echo "let swiftuiTranslationRandomDummyString$dummyname = Text(\"$dummy\")" >> Classes/SwiftuiHelpers.swift
build_configs=("Quicksy|AppStore-Quicksy", "Monal|Beta")
set +e
x=$((0))
# run several times to make sure everything gets properly extracted (is this really needed?)
while [[ $x -lt 2 ]]; do
    echo -e "${BOLD}*** STARTING RUN $x... ***${NC}"
    for entry in "${build_configs[@]}"; do
        scheme="${entry%%|*}"
        configuration="${entry#*|}"
        errcount=$((0))
        while [[ $errcount -lt 10 ]]; do
            if [[ $errcount == 0 ]]; then
                echo -e "${BOLD}*** BUILDING FOR '$scheme' - '$configuration', TRY $errcount... ***"
            else
                echo -e "${YELLOW}*** ⚠️ BUILDING FOR '$scheme' - '$configuration', TRY $errcount... ***"
            fi
            if build_and_extract_xliff "$scheme" "$configuration"; then
                echo "*** BUILD FOR '$scheme' - '$configuration', TRY $errcount SUCCEEDED... ***"
                break
            fi
            errcount=$((errcount+1))
        done
        if [[ $errcount -ge 10 ]]; then
            echo -e "${RED}❌ TOO MUCH ERRORS, ABORTING!!!${NC}"
            exit 2
        fi
    done
    echo -e "${BOLD}*** RUN $x COMPLETED! ***${NC}"
    if ! grep -q "$dummy" "localization/external/Base.lproj/Localizable.strings"; then
        echo -e "${RED}❌ COULD NOT EXTRACT DUMMY STRING, RETRYING!${NC}"
        continue
    else
        echo -e "${GREEN}✅ SUCCESSFULLY EXTRACTED DUMMY STRING...${NC}"
    fi
    x=$((x+1))
done
set -e
mv Classes/SwiftuiHelpers.swift.orig Classes/SwiftuiHelpers.swift
rm -rf *A\ Document\ Being\ Saved\ By\ xcodebuild*
if [ -e localization.tmp ]; then
    rm -rf localization.tmp
fi
if ! grep -q "$dummy" "localization/external/Base.lproj/Localizable.strings"; then
    echo "Could not extract dummy string after $x runs!"
    exit 1
fi
awk "!/$dummy/" "localization/external/Base.lproj/Localizable.strings" > "localization/external/Base.lproj/Localizable.strings.new"
mv "localization/external/Base.lproj/Localizable.strings.new" "localization/external/Base.lproj/Localizable.strings"

echo ""
echo "*********************************************************"
echo "*     Using batrycrouch to update all languages         *"
echo "*********************************************************"
runBartycrouch

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
        if [[ $2 != "NOCOMMIT" ]]; then
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
