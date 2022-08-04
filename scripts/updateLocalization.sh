#/bin/bash

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
    git pull
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
    git pull
)

# Run bartycrouch
# https://github.com/Flinesoft/BartyCrouch#exclude-specific-views--nslocalizedstrings-from-localization
if which bartycrouch > /dev/null; then
    bartycrouch update -x
    bartycrouch lint -x
else
    echo "warning: BartyCrouch not installed, download it from https://github.com/Flinesoft/BartyCrouch"
fi

for folder in "localization/external" "shareSheet-iOS/localization/external"; do
    for file in $folder/*.lproj/*.strings; do
            # Remove empty lines
            sed -i '' '/^$/d' $file
            # Remove default comments that are not supported by weblate
            sed -i '' '/^\/\* No comment provided by engineer\. \*\/$/d' $file
    done
    #subshell to not leak from "cd $folder"
    (
        cd $folder
        echo "Diff of $folder:"
        git diff
        if [[ $1 != "NOCOMMIT" ]]; then
            git add -u
            git commit -m "Updated translations via BartyCrouch"
            git log -n 2
            git remote --verbose
            git push
        fi
    )
done

git submodule deinit --all -f
git submodule update --init --recursive
