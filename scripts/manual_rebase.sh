#!/bin/bash

#get dir of this script
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
cd $DIR

#reset repo to sane state
(
	git cherry-pick --abort
	git branch -D tmpcopy
) 2>/dev/null
git fetch origin
git reset --hard origin/alpha.build

#call original rebase script
./rebase.sh

if [ "$?" -ne "0" ]; then
	echo "***********************************************************************************"
	echo "REBASE FAILED, SPAWNING SHELL"
	echo "PLEASE SOLVE CONFLICTS AND CONTINUE USING: git cherry-pick --continue"
	echo "PLEASE USE exit TO EXIT THE SPAWNED SHELL ONCE THE cherry-pick IS COMPLETE"
	echo "IF YOU USE exit WHILE THE cherry-pick IS STILL IN PROGRESS, YOUR REPOSITORY"
	echo "WILL BE RESET TO THE STATE BEFORE THE MANUAL REBASE"
	echo "***********************************************************************************"
	bash
	git cherry-pick --abort 2>/dev/null		#abort any cherry-pick currently running
	if [ "$?" -ne "0" ]; then
		echo "***********************************************************************************"
		echo "CHERRY-PICK COMPLETED SUCCESSFULLY" 
		echo "***********************************************************************************"
		git branch -D tmpcopy
		git push --force-with-lease
	else
		echo "***********************************************************************************"
		echo "CHERRY-PICK *NOT* COMPLETED SUCCESSFULLY, REVERTING"
		echo "***********************************************************************************"
		git branch -D tmpcopy
		git reset --hard origin/alpha.build
	fi
fi

exit 0
