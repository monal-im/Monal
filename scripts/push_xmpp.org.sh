#!/bin/sh

# Abort on Error
set -e

cd Monal

echo ""
echo "**********************************************"
echo "* Reading buildNumber and creating timestamp *"
echo "**********************************************"
buildNumber=$(git tag --sort="v:refname" |grep "Build_iOS" | tail -n1 | sed 's/Build_iOS_//g')
timestamp="$(date -u +%FT%T)"

echo ""
echo "*********************************************"
echo "* Cloning and resetting xmpp.org repository *"
echo "*********************************************"

if [[ -e "xmpp.org" ]]; then
    rm -rf xmpp.org
fi
git clone git@xmpp.org.push.repo:monal-im/xmpp.org.git
cd xmpp.org
git config --local user.email "pushBot@monal.im"
git config --local user.name "Monal-IM-Push[BOT]"
git remote add upstream https://github.com/xsf/xmpp.org.git
git fetch upstream
git checkout -b monal-release-push
git reset --hard  upstream/master

echo ""
echo "******************************************"
echo "* Changing Monal timestamp for build $buildNumber *"
echo "******************************************"

awk '/"name": "Monal IM",/{sub(/"last_renewed": "[0-9T:-]+",$/, "\"last_renewed\": \"'$timestamp'\",", last)} NR>1{print last} {last=$0} END {print last}' data/clients.json >data/clients.json.new
cat data/clients.json.new >data/clients.json
rm data/clients.json.new

echo ""
echo "*********************************"
echo "* Creating commit for build $buildNumber *"
echo "*********************************"

git add -u
git commit -m "New timestamp for Monal stable release with build number $buildNumber"
git push --set-upstream origin monal-release-push --force

echo ""
echo "******************************************************************"
echo "* Amending last commit in master to trigger PR creating workflow *"
echo "******************************************************************"

git checkout master
git commit -C HEAD --amend --no-edit
git push --force-with-lease

echo ""
echo "***************"
echo "* Cleaning up *"
echo "***************"

cd ..
rm -rf xmpp.org


exit 0