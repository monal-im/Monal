#!/bin/sh

# Abort on Error
set -e

EPOCH=$(date +%s)
SHASUM=$(shasum -a 256 ./Monal/build/app/Monal.alpha.tar | awk '{print $1}')

echo ""
echo "*********************************************"
echo "* Cloning and resetting homebrew-monal-alpha repository *"
echo "*********************************************"

if [[ -e "homebrew-monal-alpha" ]]; then
    rm -rf homebrew-monal-alpha
fi
git clone git@github.org.homebrew-monal-alpha.push.repo:monal-im/homebrew-monal-alpha.git
cd homebrew-monal-alpha
git config --local user.email "pushBot@monal-im.org"
git config --local user.name "Monal-IM-Push[BOT]"

awk -v timestamp="$EPOCH" -v shasum="$SHASUM" 'sub(/#timestampAsVersion#/,timestamp)sub(/#macosHash#/,shasum)1'  templates/Casks/monal-alpha.rb > Casks/monal-alpha.rb

git add Casks/monal-alpha.rb
git commit -m "Publish new version"
git push

echo ""
echo "***************"
echo "* Cleaning up *"
echo "***************"

cd ..
rm -rf homebrew-monal-alpha


exit 0

