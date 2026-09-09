#!/bin/bash

DIDFAIL=0

git add -A || FAILED=1
git commit --allow-empty -am "automatic commit: from the dangerouslyDeployImmediately.sh script" || FAILED=1

./promoteSite.sh || FAILED=1

git push

exit $FAILED