#!/bin/bash

DIDFAIL=0

cd "$(dirname "$0")" || exit 1

git add -A || DIDFAIL=1
git commit --allow-empty -am "automatic commit: from the dangerouslyDeployImmediately.sh script" || DIDFAIL=1

./promoteSite.sh || DIDFAIL=1

git push # nbd if this fails

exit $DIDFAIL