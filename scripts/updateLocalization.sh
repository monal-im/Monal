#/bin/bash

cd "$(dirname "$0")"
cd ../Monal

# for folder in "localization/external" "shareSheet-iOS/localization/external"; do
#     git fetch origin
#     git reset --hard origin/main
# done

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
#     git add -u
#     git status
#     git commit -m "Updated translations"
#     git push
done
