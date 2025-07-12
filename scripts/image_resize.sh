#!/bin/bash

if [[ "$1" == "" || "$2" == "" ]]; then
    echo "Usage: $(basename "$0") <original_logo.png> <original_dark_logo.png> [type, for example: 'Alpha']"
    exit 1
fi

type="$3"
    
for d in ./Images.xcassets/${type}AppIcon.appiconset ./Images.xcassets/${type}AppLogo.imageset; do
    for png in $d/*.png; do
        size="$(identify -format "%wx%h" "$png")"
        echo "$png ($size)"
        src="$1"
        if [[ $png =~ ^.*_[dD][aA][rR][kK]\.[pP][nN][gG]$ ]]; then
            src="$2"
        fi
        #mv "$png" "${png%.png}.old"
        convert "$src" -alpha off -filter triangle -resize "$size" "$png"
    done
done;
