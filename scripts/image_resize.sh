#!/bin/bash

if [[ "$1" == "" ]]; then
    echo "Usage: $(basename "$0") <original_logo.png> [type, for example: 'Alpha']"
    exit 1
fi

type="$2"
    
for d in ./Images.xcassets/${type}AppIcon.appiconset ./Images.xcassets/${type}AppLogo.imageset; do
	for png in $d/*.png; do
		size="$(identify -format "%wx%h" "$png")"
		echo "$png ($size)"
		#mv "$png" "${png%.png}.old"
		convert "$1" -alpha off -filter triangle -resize "$size" "$png"
	done
done;
