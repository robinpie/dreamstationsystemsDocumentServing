#!/bin/bash
# post-commit / post-merge. Stages only — see stage-site.sh. Going live is
# ./promote-site.sh, by hand, and no hook runs it.
exec "$(git rev-parse --show-toplevel)/stage-site.sh"
