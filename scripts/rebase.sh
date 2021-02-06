#!/bin/bash
set -e
set -x
PS4='${LINENO}: '
date
git config push.default simple
#git config user.email thilo@eightysoft.de
git config user.name 'Rebase-Bot'
git fetch origin/develop
git fetch origin/alpha.build
date
git branch tmpcopy
git log origin/alpha.build..origin/develop > ../changes.txt
first="$(git log --grep='\*\*\* INITIAL ALPHA COMMIT \*\*\*' --since='Mon Jun 8 16:33:25 2020 +0200' --author='tmolitor-stud-tu' --oneline --no-abbrev-commit tmpcopy | awk '{print $1}')"
echo "FIRST: $first"
exit 0
git reset --hard origin/develop
touch ../changes.txt
ls -l ../changes.txt
mv ../changes.txt changes.txt
git add changes.txt
git commit -m "Add newest changes.txt"
git cherry-pick $first^..tmpcopy
#this would contain old commits now rebased/changed in Monal
#git cherry-pick develop..tmpcopy
git branch -D tmpcopy
date
git push --force-with-lease
