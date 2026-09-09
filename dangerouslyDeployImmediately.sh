#!/bin/bash

DIDFAIL=0

git add -A || DIDFAIL=1
git commit --allow-empty -am "automatic commit: from the dangerouslyDeployImmediately.sh script" || DIDFAIL=1

./promoteSite.sh || DIDFAIL=1

git push

exit $FAILED