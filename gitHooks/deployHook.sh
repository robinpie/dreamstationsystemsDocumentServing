#!/bin/bash
# post-commit / post-merge. Stages only — see stageSite.sh. Going live is
# ./promoteSite.sh, by hand, and no hook runs it.
exec "$(git rev-parse --show-toplevel)/stageSite.sh"
