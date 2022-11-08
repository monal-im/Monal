#/bin/bash

set -e

cd "$(dirname "$0")"
cd ../Monal

git submodule deinit --all -f
git submodule update --init --recursive --remote

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

# extract xliff file (has to be run multiple times, even if no error occured, don't ask me why)
# we use grep here to test for a dummy string to detect if our run succeeded
if [ -e localization.tmp ]; then
    rm -rf localization.tmp
fi
x=$((1))
while [[ $x < 8 ]]; do
    echo "RUN $x..."
    while ! xcrun xcodebuild -exportLocalizations -localizationPath localization.tmp -exportLanguage base SWIFT_EMIT_LOC_STRINGS=NO; do
        echo "ERROR, TRYING AGAIN..."
    done
    if grep -q 'Dummy string to test SwiftUI translation support.' "localization.tmp/base.xcloc/Localized Contents/base.xliff"; then
        echo "SUCCESS!"
        break
    fi
    x=$((x+1))
done
rm -rf *A\ Document\ Being\ Saved\ By\ xcodebuild*
if [[ $x == 8 ]]; then
    echo "Could not extract dummy string!"
    exit 1
fi

# Run bartycrouch
# https://github.com/Flinesoft/BartyCrouch#exclude-specific-views--nslocalizedstrings-from-localization
if which bartycrouch > /dev/null; then
    # extract additional strings from xliff file and add them to our strings file (bartycrouch will remove duplicates later on)
    ../scripts/xliff_extractor.py -x "localization.tmp/base.xcloc/Localized Contents/base.xliff"
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
else
    echo "warning: BartyCrouch not installed, download it from https://github.com/Flinesoft/BartyCrouch"
    exit 1
fi

if [ -e localization.tmp ]; then
    rm -rf localization.tmp
fi

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

git submodule deinit --all -f
git submodule update --init --recursive
