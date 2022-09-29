#!/bin/bash

if [[ "$1" == "" ]]; then
    echo "Usage: $(basename "$0") <original_logo.png>"
    exit 1
fi
    
for d in ./Images.xcassets/AlphaApp*set; do
	for png in $d/*.png; do
		size="$(identify -format "%wx%h" "$png")"
		echo "$png ($size)"
		#mv "$png" "${png%.png}.old"
		convert "$1" -alpha off -filter triangle -resize "$size" "$png"
	done
done;
