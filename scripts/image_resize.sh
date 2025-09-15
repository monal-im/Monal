#!/bin/bash

# SPDX-FileCopyrightText: 2025 Thilo Molitor <info@monal-im.org>, 2024
#
# SPDX-License-Identifier: BSD-2-Clause

if [[ "$1" == "" || "$2" == "" ]]; then
    echo "Usage: $(basename "$0") <original_logo.png> <original_dark_logo.png> [type, for example: 'Alpha'] [alternate suffix, for example: '-Christmas']"
    exit 1
fi

type="$3"
suffix="$4"
    
for d in ./Images.xcassets/${type}AppIcon${suffix}.appiconset ./Images.xcassets/${type}AppLogo${suffix}.imageset; do
    if [[ -d $d ]]; then
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
    else
        echo "Ignoring non-existent directory: $d"
    fi
done;
